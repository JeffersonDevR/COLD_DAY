"""Task 3.2 — RED: integration flow of the Pacto vertical (RF-SR-003..012).

Runs against the local PostGIS database. Exercises the REAL auth + services
routers end to end (same harness as test_contract_fixes.py):

- happy cycle requested -> bidding -> diagnosis -> pact_proposed ->
  in_progress -> completed (spec scenario "Ciclo feliz completo");
- double bid acceptance -> 409 ("Doble aceptación de bid");
- competitor bids rejected atomically ("Bids competidores al aceptar");
- pact rejection reopens the market: ALL bids back to pending
  ("Rechazo del pacto reabre el mercado");
- atomic cancel with pending bids ("Cancelación con ofertas pendientes");
- illegal transition -> 409 ("Transición ilegal");
- ownership isolation 404/403 ("Aislamiento por propiedad").

References the S3 endpoints (accept bid, diagnosis, agreements, complete,
cancel, GET /my, GET detail) which do not exist yet -> guaranteed RED.
"""

import random

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text

from app.api.auth import router as auth_router
from app.api.services import router as services_router
from app.core.database import AsyncSessionLocal
from app.models.service import (
    Equipment,
    ServiceAgreement,
    ServiceRequest,
    TechnicianBid,
)
from app.models.user import User

pytestmark = pytest.mark.integration

CUCUTA_LAT, CUCUTA_LON = 7.8939, -72.5078


def _unique_document() -> str:
    return f"100{random.randint(10**8, 10**9)}"


async def _register_and_login(client: AsyncClient, role: str):
    """Register a user and return (document, access_token)."""
    document = _unique_document()
    payload = (
        {
            "full_name": "Carlos Tecnico",
            "document": document,
            "phone": "3017654321",
            "password": "ClaveSegura123",
            "specialty": "Neveras",
            "latitude": CUCUTA_LAT,
            "longitude": CUCUTA_LON,
        }
        if role == "technician"
        else {
            "full_name": "Ana Cliente",
            "document": document,
            "phone": "3001234567",
            "password": "ClaveSegura123",
        }
    )
    reg = await client.post(f"/api/auth/register/{role}", json=payload)
    assert reg.status_code == 201
    login = await client.post(
        "/api/auth/login",
        json={"document": document, "password": "ClaveSegura123"},
    )
    assert login.status_code == 200
    return document, login.json()["access_token"]


async def _register_verified_technician(client: AsyncClient):
    """Register a technician and flip the profile to `verified`.

    Returns (document, access_token, technician_id).
    """
    document, token = await _register_and_login(client, "technician")
    async with AsyncSessionLocal() as session:
        user = (
            await session.execute(select(User).where(User.document == document))
        ).scalar_one()
        await session.execute(
            text(
                "UPDATE technicians SET verification_status = 'verified' "
                "WHERE user_id = :u"
            ),
            {"u": user.id},
        )
        await session.commit()
        tech_id = (
            await session.execute(
                text("SELECT id FROM technicians WHERE user_id = :u"),
                {"u": user.id},
            )
        ).scalar_one()
    return document, token, tech_id


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _create_request(
    client: AsyncClient,
    client_token: str,
    *,
    description: str = "Aire acondicionado no enfría",
) -> int:
    async with AsyncSessionLocal() as session:
        equipment_id = (
            await session.execute(select(Equipment.id).order_by(Equipment.id).limit(1))
        ).scalar_one()
    response = await client.post(
        "/api/services/",
        headers=_auth(client_token),
        json={
            "equipment_id": equipment_id,
            "service_type": "repair",
            "description": description,
            "latitude": CUCUTA_LAT,
            "longitude": CUCUTA_LON,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["request_id"]


async def _create_bid(
    client: AsyncClient,
    tech_token: str,
    request_id: int,
    *,
    transport_cost: float = 15000,
    diagnosis_cost: float = 35000,
) -> int:
    response = await client.post(
        "/api/services/bids/",
        headers=_auth(tech_token),
        json={
            "service_request_id": request_id,
            "price_offered": 80000,
            "estimated_time_minutes": 45,
            "transport_cost": transport_cost,
            "diagnosis_cost": diagnosis_cost,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["bid_id"]


async def _accept_bid(
    client: AsyncClient, client_token: str, request_id: int, bid_id: int
):
    return await client.post(
        f"/api/services/{request_id}/bids/{bid_id}/accept",
        headers=_auth(client_token),
    )


async def _register_diagnosis(
    client: AsyncClient,
    tech_token: str,
    request_id: int,
    observations: str = "Fuga de gas en la línea de alta",
):
    return await client.post(
        f"/api/services/{request_id}/diagnosis",
        headers=_auth(tech_token),
        json={"observations": observations},
    )


async def _create_agreement(
    client: AsyncClient,
    tech_token: str,
    request_id: int,
    *,
    labor_cost: float = 80000,
    transport_cost: float = 15000,
    diagnosis_cost: float = 35000,
):
    return await client.post(
        f"/api/services/{request_id}/agreements/",
        headers=_auth(tech_token),
        json={
            "labor_cost": labor_cost,
            "transport_cost": transport_cost,
            "diagnosis_cost": diagnosis_cost,
            "observations": "Fuga de gas en la línea de alta",
        },
    )


async def _row_statuses(request_id: int) -> dict:
    """Snapshot del estado en DB (request/bids/agreements) para asserts atómicos."""
    async with AsyncSessionLocal() as session:
        req = (
            await session.execute(
                select(ServiceRequest).where(ServiceRequest.id == request_id)
            )
        ).scalar_one()
        bids = (
            await session.execute(
                select(TechnicianBid).where(
                    TechnicianBid.service_request_id == request_id
                )
            )
        ).scalars().all()
        pacts = (
            await session.execute(
                select(ServiceAgreement).where(
                    ServiceAgreement.service_request_id == request_id
                )
            )
        ).scalars().all()
    return {
        "request_status": req.status,
        "assigned_technician_id": req.assigned_technician_id,
        "diagnosis_observations": req.diagnosis_observations,
        "bid_statuses": sorted(b.status for b in bids),
        "pact_statuses": sorted(p.status for p in pacts),
    }


@pytest.fixture
async def client():
    """Test app: real auth + services routers (real get_db / get_current_user)."""
    app = FastAPI()
    app.include_router(auth_router)
    app.include_router(services_router)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture(autouse=True)
async def _cleanup_after_each_test():
    """Aisla cada test: borra todo lo creado con documentos de prueba '100...'.

    Orden de FK: agreements -> bids -> requests -> technicians -> users.
    """
    yield
    async with AsyncSessionLocal() as session:
        await session.execute(
            text(
                "DELETE FROM auth_tokens WHERE user_id IN "
                f"(SELECT id FROM users WHERE document LIKE '100%')"
            )
        )
        await session.execute(
            text(
                "DELETE FROM service_agreements WHERE service_request_id IN "
                f"(SELECT id FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE document LIKE '100%'))"
            )
        )
        await session.execute(
            text(
                "DELETE FROM technician_bids WHERE service_request_id IN "
                f"(SELECT id FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE document LIKE '100%'))"
            )
        )
        await session.execute(
            text(
                f"DELETE FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE document LIKE '100%')"
            )
        )
        await session.execute(text("DELETE FROM technicians WHERE user_id IS NOT NULL"))
        await session.execute(text("DELETE FROM users WHERE document LIKE '100%'"))
        await session.commit()


# --- Escenario: Ciclo feliz completo (RF-SR-003..008) -------------------------

async def test_happy_cycle_requested_to_completed(client):
    _, client_token = await _register_and_login(client, "client")
    tech_doc, tech_token, tech_id = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)

    # 1. El técnico oferta -> requested -> bidding
    bid_id = await _create_bid(client, tech_token, request_id)

    # 2. El cliente dueño acepta el bid -> bidding -> diagnosis
    accept = await _accept_bid(client, client_token, request_id, bid_id)
    assert accept.status_code == 200
    assert accept.json()["status"] == "diagnosis"

    # 3. El técnico asignado registra el diagnóstico (RF-SR-004)
    diag = await _register_diagnosis(client, tech_token, request_id)
    assert diag.status_code == 200

    # 4. El técnico propone el pacto -> diagnosis -> pact_proposed (RF-SR-005)
    pact = await _create_agreement(client, tech_token, request_id)
    assert pact.status_code == 201
    body = pact.json()
    agreement_id = body["agreement_id"]
    assert body["total"] == 130000  # 80000 + 15000 + 35000 (price_offered NO entra)

    # 5. El cliente dueño acepta el pacto -> pact_proposed -> in_progress
    accept_pact = await client.post(
        f"/api/services/{request_id}/agreements/{agreement_id}/accept",
        headers=_auth(client_token),
    )
    assert accept_pact.status_code == 200
    assert accept_pact.json()["status"] == "in_progress"

    # 6. El técnico asignado finaliza -> in_progress -> completed (RF-SR-008)
    done = await client.post(
        f"/api/services/{request_id}/complete", headers=_auth(tech_token)
    )
    assert done.status_code == 200
    assert done.json()["status"] == "completed"

    # Estado final en DB: request completed, bid accepted, pacto accepted.
    state = await _row_statuses(request_id)
    assert state["request_status"] == "completed"
    assert state["assigned_technician_id"] == tech_id
    assert state["bid_statuses"] == ["accepted"]
    assert state["pact_statuses"] == ["accepted"]
    assert state["diagnosis_observations"] == "Fuga de gas en la línea de alta"

    # El dueño ve el detalle con técnico + línea de tiempo (RF-SR-010).
    detail = await client.get(
        f"/api/services/{request_id}", headers=_auth(client_token)
    )
    assert detail.status_code == 200
    body = detail.json()
    assert body["status"] == "completed"
    assert body["technician"]["id"] == tech_id
    assert body["technician"]["name"] == "Carlos Tecnico"
    assert body["diagnosis_observations"] == "Fuga de gas en la línea de alta"
    assert len(body["timeline"]["bids"]) == 1
    assert len(body["timeline"]["agreements"]) == 1
    assert body["timeline"]["bids"][0]["status"] == "accepted"
    assert body["timeline"]["agreements"][0]["status"] == "accepted"
    assert body["timeline"]["agreements"][0]["total"] == 130000

    # Historial del dueño (fecha desc) incluye la solicitud con el técnico.
    history = await client.get("/api/services/my", headers=_auth(client_token))
    assert history.status_code == 200
    mine = {item["id"]: item for item in history.json()["requests"]}
    assert request_id in mine
    assert mine[request_id]["status"] == "completed"
    assert mine[request_id]["technician"]["name"] == "Carlos Tecnico"


# --- Escenario: Doble aceptación de bid (RF-SR-003) ---------------------------

async def test_accepting_second_bid_after_first_returns_409(client):
    _, client_token = await _register_and_login(client, "client")
    _, tech_token_a, _ = await _register_verified_technician(client)
    _, tech_token_b, _ = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)

    bid_a = await _create_bid(client, tech_token_a, request_id)
    bid_b = await _create_bid(client, tech_token_b, request_id)

    first = await _accept_bid(client, client_token, request_id, bid_a)
    assert first.status_code == 200

    # Aceptar el segundo bid (o el mismo de nuevo) fuera de `bidding` -> 409.
    second = await _accept_bid(client, client_token, request_id, bid_b)
    assert second.status_code == 409
    again = await _accept_bid(client, client_token, request_id, bid_a)
    assert again.status_code == 409

    # Los intentos 409 no modifican NADA: B quedó rejected al aceptar A
    # (competidores atómicos, RF-SR-003) y sigue rejected; el request sigue
    # en diagnosis.
    state = await _row_statuses(request_id)
    assert state["request_status"] == "diagnosis"
    assert state["bid_statuses"] == ["accepted", "rejected"]


# --- Escenario: Bids competidores al aceptar (RF-SR-003, atómico) -------------

async def test_accepting_bid_rejects_competitors_atomically(client):
    _, client_token = await _register_and_login(client, "client")
    _, tech_token_a, tech_a_id = await _register_verified_technician(client)
    _, tech_token_b, _ = await _register_verified_technician(client)
    _, tech_token_c, _ = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)

    bid_a = await _create_bid(client, tech_token_a, request_id)
    await _create_bid(client, tech_token_b, request_id)
    await _create_bid(client, tech_token_c, request_id)

    accept = await _accept_bid(client, client_token, request_id, bid_a)
    assert accept.status_code == 200

    # Un commit: A accepted, B y C rejected, request diagnosis, asignación real.
    state = await _row_statuses(request_id)
    assert state["request_status"] == "diagnosis"
    assert state["assigned_technician_id"] == tech_a_id
    assert state["bid_statuses"] == ["accepted", "rejected", "rejected"]


# --- Escenario: Rechazo del pacto reabre el mercado (RF-SR-007) ---------------

async def test_rejecting_pact_returns_all_bids_to_pending(client):
    _, client_token = await _register_and_login(client, "client")
    _, tech_token_a, tech_a_id = await _register_verified_technician(client)
    _, tech_token_b, _ = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)

    await _create_bid(client, tech_token_a, request_id)
    await _create_bid(client, tech_token_b, request_id)

    # Asignación: A gana, B queda rejected.
    async with AsyncSessionLocal() as session:
        bid_a_id = (
            await session.execute(
                select(TechnicianBid.id).where(
                    TechnicianBid.service_request_id == request_id,
                    TechnicianBid.technician_id == tech_a_id,
                )
            )
        ).scalar_one()
    accept = await _accept_bid(client, client_token, request_id, bid_a_id)
    assert accept.status_code == 200

    await _register_diagnosis(client, tech_token_a, request_id)
    pact = await _create_agreement(client, tech_token_a, request_id)
    agreement_id = pact.json()["agreement_id"]

    # El cliente rechaza el pacto -> mercado reabre.
    reject = await client.post(
        f"/api/services/{request_id}/agreements/{agreement_id}/reject",
        headers=_auth(client_token),
    )
    assert reject.status_code == 200
    assert reject.json()["status"] == "bidding"

    state = await _row_statuses(request_id)
    assert state["request_status"] == "bidding"
    assert state["pact_statuses"] == ["rejected"]  # el pacto queda como histórico
    # TODOS los bids vuelven a pending (A y B), incluido el rechazado al asignar.
    assert state["bid_statuses"] == ["pending", "pending"]


# --- Escenario: Cancelación con ofertas pendientes (RF-SR-009, atómico) ------

async def test_cancel_with_pending_bids_rejects_them_atomically(client):
    _, client_token = await _register_and_login(client, "client")
    _, tech_token_a, _ = await _register_verified_technician(client)
    _, tech_token_b, _ = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)

    await _create_bid(client, tech_token_a, request_id)
    await _create_bid(client, tech_token_b, request_id)

    cancel = await client.post(
        f"/api/services/{request_id}/cancel", headers=_auth(client_token)
    )
    assert cancel.status_code == 200
    assert cancel.json()["status"] == "cancelled"

    state = await _row_statuses(request_id)
    assert state["request_status"] == "cancelled"
    assert state["bid_statuses"] == ["rejected", "rejected"]


# --- Escenario: Transición ilegal (spec §3) -----------------------------------

async def test_complete_from_requested_returns_409(client):
    _, client_token = await _register_and_login(client, "client")
    _, tech_token, _ = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)

    # Solicitud en `requested`: finalizar es una transición ilegal -> 409.
    done = await client.post(
        f"/api/services/{request_id}/complete", headers=_auth(tech_token)
    )
    assert done.status_code == 409

    # Cancelar desde `diagnosis` en adelante también es ilegal (RN-003).
    bid_id = await _create_bid(client, tech_token, request_id)
    assert (
        await _accept_bid(client, client_token, request_id, bid_id)
    ).status_code == 200
    late_cancel = await client.post(
        f"/api/services/{request_id}/cancel", headers=_auth(client_token)
    )
    assert late_cancel.status_code == 409


# --- Escenario: Aislamiento por propiedad (RF-SR-012) -------------------------

async def test_ownership_isolation_returns_404_and_403(client):
    # Cliente A dueño + técnicos: llevar la solicitud hasta in_progress.
    _, client_token_a = await _register_and_login(client, "client")
    _, tech_token_a, _ = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token_a)
    bid_id = await _create_bid(client, tech_token_a, request_id)
    assert (
        await _accept_bid(client, client_token_a, request_id, bid_id)
    ).status_code == 200
    await _register_diagnosis(client, tech_token_a, request_id)
    pact = await _create_agreement(client, tech_token_a, request_id)
    agreement_id = pact.json()["agreement_id"]
    assert (
        await client.post(
            f"/api/services/{request_id}/agreements/{agreement_id}/accept",
            headers=_auth(client_token_a),
        )
    ).status_code == 200

    # Cliente B: NO ve ni toca la solicitud ajena -> 404 (RF-SR-012).
    _, client_token_b = await _register_and_login(client, "client")
    other = await client.get(
        f"/api/services/{request_id}", headers=_auth(client_token_b)
    )
    assert other.status_code == 404
    foreign_accept = await _accept_bid(client, client_token_b, request_id, bid_id)
    assert foreign_accept.status_code == 404
    foreign_cancel = await client.post(
        f"/api/services/{request_id}/cancel", headers=_auth(client_token_b)
    )
    assert foreign_cancel.status_code == 404
    foreign_pact = await client.post(
        f"/api/services/{request_id}/agreements/{agreement_id}/reject",
        headers=_auth(client_token_b),
    )
    assert foreign_pact.status_code == 404

    # El historial de B no lista la solicitud de A.
    history = await client.get("/api/services/my", headers=_auth(client_token_b))
    assert history.status_code == 200
    assert request_id not in {r["id"] for r in history.json()["requests"]}

    # Técnico C (no asignado) no puede finalizar -> 403 ni ver el detalle -> 404.
    _, tech_token_c, _ = await _register_verified_technician(client)
    intruder = await client.post(
        f"/api/services/{request_id}/complete", headers=_auth(tech_token_c)
    )
    assert intruder.status_code == 403
    intruder_detail = await client.get(
        f"/api/services/{request_id}", headers=_auth(tech_token_c)
    )
    assert intruder_detail.status_code == 404
