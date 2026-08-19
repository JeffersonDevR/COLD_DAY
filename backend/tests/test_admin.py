"""Task 5.1 — RED: dashboard admin (RF-ADM-001..008).

Integración contra PostGIS local (mismo harness que test_reviews.py): routers
REALES auth + services + admin. Escenarios de la spec §6 admin-dashboard:

- KPIs correctos: 5 clientes / 6 técnicos (2 pending) / 10 solicitudes con
  desglose por estado (4 requested, 3 bidding, 2 in_progress, 1 completed) —
  RF-ADM-002;
- Aprobación de técnico: pending -> verified (RF-ADM-005);
- Rechazo sin motivo -> 422 exigiendo el motivo; con motivo -> rejected + razón
  guardada (RF-ADM-005, NFR motivo obligatorio);
- Verificación no secuencial: verify/reject sobre técnico que ya NO está
  pending -> 409 (RF-ADM-008);
- Acceso exclusivo: rol distinto de admin -> 403; sin token -> 401 (RF-ADM-007);
- Listas de clientes/técnicos (RF-ADM-003/004) y monitoreo de solicitudes con
  filtro por estado (RF-ADM-006).

Referencia el router `app.api.admin` y el schemas `app.schemas.admin`, que no
existen todavía -> RED garantizado.
"""

import random

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text

from app.api.admin import router as admin_router
from app.api.auth import router as auth_router
from app.api.services import router as services_router
from app.core.database import AsyncSessionLocal
from app.models.service import Equipment
from app.models.user import User

pytestmark = pytest.mark.integration

CUCUTA_LAT, CUCUTA_LON = 7.8939, -72.5078


def _unique_document() -> str:
    return f"100{random.randint(10**8, 10**9)}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _register_and_login(client: AsyncClient, role: str):
    """Registra un usuario y devuelve (document, access_token)."""
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
    assert reg.status_code == 201, reg.text
    login = await client.post(
        "/api/auth/login",
        json={"document": document, "password": "ClaveSegura123"},
    )
    assert login.status_code == 200, login.text
    return document, login.json()["access_token"]


async def _register_only(client: AsyncClient, role: str) -> str:
    """Registra sin login (bulk KPI); devuelve el documento."""
    document = _unique_document()
    payload = (
        {
            "full_name": f"Tecnico Bulk {document[-4:]}",
            "document": document,
            "phone": "3017654321",
            "password": "ClaveSegura123",
            "specialty": "Aire acondicionado",
            "latitude": CUCUTA_LAT,
            "longitude": CUCUTA_LON,
        }
        if role == "technician"
        else {
            "full_name": f"Cliente Bulk {document[-4:]}",
            "document": document,
            "phone": "3001234567",
            "password": "ClaveSegura123",
        }
    )
    reg = await client.post(f"/api/auth/register/{role}", json=payload)
    assert reg.status_code == 201, reg.text
    return document


async def _create_admin(client: AsyncClient) -> tuple[str, str]:
    """Admin de prueba: registra un cliente y promueve su rol en DB (RF-ADM-001)."""
    document = _unique_document()
    reg = await client.post(
        "/api/auth/register/client",
        json={
            "full_name": "Administrador Prueba",
            "document": document,
            "phone": "3001112233",
            "password": "ClaveSegura123",
        },
    )
    assert reg.status_code == 201, reg.text
    async with AsyncSessionLocal() as session:
        user_id = (
            await session.execute(select(User.id).where(User.document == document))
        ).scalar_one()
        await session.execute(
            text("UPDATE users SET role = 'admin' WHERE id = :u"), {"u": user_id}
        )
        await session.commit()
    login = await client.post(
        "/api/auth/login",
        json={"document": document, "password": "ClaveSegura123"},
    )
    assert login.status_code == 200, login.text
    return document, login.json()["access_token"]


async def _technician_id(document: str) -> int:
    async with AsyncSessionLocal() as session:
        return (
            await session.execute(
                text(
                    "SELECT t.id FROM technicians t JOIN users u ON u.id = t.user_id "
                    "WHERE u.document = :d"
                ),
                {"d": document},
            )
        ).scalar_one()


async def _set_verification(documents: list[str], status: str) -> None:
    """Cambia verification_status de técnicos de prueba (set up de estado)."""
    async with AsyncSessionLocal() as session:
        for doc in documents:
            await session.execute(
                text(
                    "UPDATE technicians SET verification_status = :s WHERE user_id IN "
                    "(SELECT id FROM users WHERE document = :d)"
                ),
                {"s": status, "d": doc},
            )
        await session.commit()


async def _set_request_statuses(ids: list[int], status: str) -> None:
    """Cambia el status de solicitudes de prueba (set up del desglose)."""
    async with AsyncSessionLocal() as session:
        for rid in ids:
            await session.execute(
                text("UPDATE service_requests SET status = :s WHERE id = :rid"),
                {"s": status, "rid": rid},
            )
        await session.commit()


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


@pytest.fixture
async def client():
    """App de tests: routers reales auth + services + admin."""
    app = FastAPI()
    app.include_router(auth_router)
    app.include_router(services_router)
    app.include_router(admin_router)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture(autouse=True)
async def _cleanup_after_each_test():
    """Aísla cada test: borra todo lo creado con documentos de prueba '100...'."""
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
        await session.execute(
            text("DELETE FROM technicians WHERE user_id IS NOT NULL")
        )
        await session.execute(text("DELETE FROM users WHERE document LIKE '100%'"))
        await session.commit()


# --- Escenario: KPIs correctos (RF-ADM-002) -----------------------------------

async def test_kpis_counts_and_breakdown(client):
    """5 clientes, 6 técnicos (2 pending), 10 solicitudes (4/3/2/1) nuevos.

    El desglose del escenario spec: 4 requested, 3 bidding, 2 in_progress,
    1 completed -> KPIs se incrementan 5/6/2 + desglose. Se mide contra un
    baseline (la DB dev puede tener técnicos/solicitudes legacy) y se
    comprueba el DELTA exacto que aportan los datos de prueba.
    """
    _, admin_token = await _create_admin(client)
    baseline = (await client.get("/api/admin/kpis", headers=_auth(admin_token))).json()

    # 5 clientes (login del primero para crear solicitudes autenticadas).
    client_docs = [await _register_only(client, "client") for _ in range(4)]
    client1_doc, client1_token = await _register_and_login(client, "client")
    client_docs.append(client1_doc)
    # 6 técnicos, 4 pasan a verified -> 2 quedan pending (RF-ADM-002).
    tech_docs = [await _register_only(client, "technician") for _ in range(6)]
    await _set_verification(tech_docs[:4], "verified")

    # 10 solicitudes vía API (RF-SR-001) y el desglose se fija por SQL.
    request_ids = [
        await _create_request(client, client1_token, description=f"Solicitud {i}")
        for i in range(10)
    ]
    await _set_request_statuses(request_ids[4:7], "bidding")
    await _set_request_statuses(request_ids[7:9], "in_progress")
    await _set_request_statuses(request_ids[9:10], "completed")
    # request_ids[0:4] quedan `requested` (default).

    resp = await client.get("/api/admin/kpis", headers=_auth(admin_token))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["total_clients"] == baseline["total_clients"] + 5
    assert body["total_technicians"] == baseline["total_technicians"] + 6
    assert body["pending_technicians"] == baseline["pending_technicians"] + 2
    by_status = body["requests_by_status"]
    base_by_status = baseline["requests_by_status"]
    assert by_status["requested"] == base_by_status["requested"] + 4
    assert by_status["bidding"] == base_by_status["bidding"] + 3
    assert by_status["diagnosis"] == base_by_status["diagnosis"]
    assert by_status["pact_proposed"] == base_by_status["pact_proposed"]
    assert by_status["in_progress"] == base_by_status["in_progress"] + 2
    assert by_status["completed"] == base_by_status["completed"] + 1
    assert by_status["cancelled"] == base_by_status["cancelled"]


# --- Escenario: Aprobación de técnico (RF-ADM-005) ----------------------------

async def test_verify_pending_technician_approves(client):
    """Técnico pending en la cola -> verify -> verified (aparece en radar)."""
    _, admin_token = await _create_admin(client)
    tech_doc, _ = await _register_and_login(client, "technician")
    tech_id = await _technician_id(tech_doc)

    resp = await client.post(
        f"/api/admin/technicians/{tech_id}/verify", headers=_auth(admin_token)
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["verification_status"] == "verified"

    async with AsyncSessionLocal() as session:
        status = (
            await session.execute(
                text("SELECT verification_status FROM technicians WHERE id = :t"),
                {"t": tech_id},
            )
        ).scalar_one()
        assert status == "verified"


# --- Escenario: Rechazo sin motivo (RF-ADM-005, NFR) --------------------------

async def test_reject_without_reason_returns_422_and_with_reason_rejects(client):
    """Sin motivo (ni body, ni reason vacío) -> 422; con motivo -> rejected."""
    _, admin_token = await _create_admin(client)
    tech_doc, _ = await _register_and_login(client, "technician")
    tech_id = await _technician_id(tech_doc)

    # Sin body -> 422 (motivo obligatorio).
    no_body = await client.post(
        f"/api/admin/technicians/{tech_id}/reject", headers=_auth(admin_token)
    )
    assert no_body.status_code == 422

    # reason vacío -> 422 (422 por campo, no 409).
    empty = await client.post(
        f"/api/admin/technicians/{tech_id}/reject",
        headers=_auth(admin_token),
        json={"reason": ""},
    )
    assert empty.status_code == 422

    # El técnico sigue pending tras los rechazos fallidos.
    async with AsyncSessionLocal() as session:
        status = (
            await session.execute(
                text("SELECT verification_status FROM technicians WHERE id = :t"),
                {"t": tech_id},
            )
        ).scalar_one()
        assert status == "pending"

    # Con motivo -> rejected + motivo guardado (RF-TEC-003).
    with_reason = await client.post(
        f"/api/admin/technicians/{tech_id}/reject",
        headers=_auth(admin_token),
        json={"reason": "Documentación incompleta"},
    )
    assert with_reason.status_code == 200, with_reason.text
    assert with_reason.json()["verification_status"] == "rejected"

    async with AsyncSessionLocal() as session:
        reason = (
            await session.execute(
                text("SELECT rejection_reason FROM technicians WHERE id = :t"),
                {"t": tech_id},
            )
        ).scalar_one()
        assert reason == "Documentación incompleta"


# --- Escenario: Verificación no secuencial (RF-ADM-008) -----------------------

async def test_verify_or_reject_non_pending_returns_409(client):
    """Técnico ya verified: verify otra vez -> 409; reject -> 409."""
    _, admin_token = await _create_admin(client)
    tech_doc, _ = await _register_and_login(client, "technician")
    tech_id = await _technician_id(tech_doc)
    await _set_verification([tech_doc], "verified")

    again = await client.post(
        f"/api/admin/technicians/{tech_id}/verify", headers=_auth(admin_token)
    )
    assert again.status_code == 409

    reject_verified = await client.post(
        f"/api/admin/technicians/{tech_id}/reject",
        headers=_auth(admin_token),
        json={"reason": "Cambio de opinión"},
    )
    assert reject_verified.status_code == 409

    # Nada se modificó: sigue verified.
    async with AsyncSessionLocal() as session:
        status = (
            await session.execute(
                text("SELECT verification_status FROM technicians WHERE id = :t"),
                {"t": tech_id},
            )
        ).scalar_one()
        assert status == "verified"


# --- Escenario: Acceso denegado (RF-ADM-007) ----------------------------------

async def test_non_admin_access_returns_403(client):
    """Cliente o técnico autenticado -> 403; sin token -> 401 (RF-ADM-007)."""
    _, admin_token = await _create_admin(client)
    await client.get("/api/admin/kpis", headers=_auth(admin_token))  # sanity: admin sí

    _, client_token = await _register_and_login(client, "client")
    client_kpis = await client.get("/api/admin/kpis", headers=_auth(client_token))
    assert client_kpis.status_code == 403

    _, tech_token = await _register_and_login(client, "technician")
    tech_kpis = await client.get("/api/admin/kpis", headers=_auth(tech_token))
    assert tech_kpis.status_code == 403

    anon = await client.get("/api/admin/kpis")
    assert anon.status_code == 401


# --- Listas de clientes / técnicos (RF-ADM-003/004) ---------------------------

async def test_lists_clients_and_technicians(client):
    _, admin_token = await _create_admin(client)
    client_doc, _ = await _register_and_login(client, "client")
    tech_doc, _ = await _register_and_login(client, "technician")
    tech_id = await _technician_id(tech_doc)

    # La lista de clientes incluye al cliente de prueba con sus campos y al
    # admin NO (fue promovido desde client -> rol admin).
    clients = await client.get("/api/admin/users/clients", headers=_auth(admin_token))
    assert clients.status_code == 200, clients.text
    client_rows = [
        row for row in clients.json()["clients"] if row["document"] == client_doc
    ]
    assert len(client_rows) == 1
    assert {"full_name", "document", "phone", "created_at"} <= set(client_rows[0])

    # La lista de técnicos incluye al técnico de prueba (pending) con campos.
    technicians = await client.get(
        "/api/admin/users/technicians", headers=_auth(admin_token)
    )
    assert technicians.status_code == 200, technicians.text
    tech_rows = [
        row
        for row in technicians.json()["technicians"]
        if row["id"] == tech_id
    ]
    assert len(tech_rows) == 1
    row = tech_rows[0]
    assert {"name", "specialty", "verification_status", "rating"} <= set(row)
    assert row["specialty"] == "Neveras"
    assert row["verification_status"] == "pending"
    assert row["rating"] == 0.0


# --- Monitoreo de solicitudes con filtro (RF-ADM-006) -------------------------

async def test_requests_monitoring_filters_by_status(client):
    _, admin_token = await _create_admin(client)
    _, client_token = await _register_and_login(client, "client")
    r1 = await _create_request(client, client_token, description="Primera")
    r2 = await _create_request(client, client_token, description="Segunda")
    await _set_request_statuses([r2], "bidding")

    all_resp = await client.get("/api/admin/requests", headers=_auth(admin_token))
    assert all_resp.status_code == 200, all_resp.text
    all_ids = {row["id"] for row in all_resp.json()["requests"]}
    assert {r1, r2} <= all_ids  # ambas solicitudes de prueba sí están listadas

    filtered = await client.get(
        "/api/admin/requests?status=bidding", headers=_auth(admin_token)
    )
    assert filtered.status_code == 200, filtered.text
    rows = filtered.json()["requests"]
    filtered_ids = [row["id"] for row in rows]
    # El filtro por estado: r2 (bidding) sí, r1 (requested) NO; todo con status.
    assert r2 in filtered_ids
    assert r1 not in filtered_ids
    assert all(row["status"] == "bidding" for row in rows)
    assert rows[0]["client_name"]  # monitoreo legible para el admin