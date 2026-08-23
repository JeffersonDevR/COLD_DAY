"""Tasks 2.1/2.2 — RED: contract fixes for service requests and bids.

Covers the broken contracts repaired in S2 (RF-SR-001/002/011):
- bids without `transport_cost`/`diagnosis_cost` or with negative costs -> 422
  with a per-field error (previously accepted silently);
- `equipment_id` that does not exist -> 404 (previously a 500 because the
  `not eq and HTTPException(...)` expression never raised);
- request creation binds the authenticated user from the token: no `user_id`
  in the payload, the created request belongs to the logged-in client.

Harness: throwaway FastAPI app hosting the REAL services + auth routers against
the local PostGIS database (same pattern as test_auth.py).
"""

import random

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text

from app.api.auth import router as auth_router
from app.api.services import router as services_router
from app.core.database import AsyncSessionLocal
from app.models.service import Equipment, ServiceRequest, TechnicianBid
from app.models.user import User

pytestmark = pytest.mark.integration


def _unique_document() -> str:
    return f"100{random.randint(10**8, 10**9)}"


def _register_payload(document: str, role: str) -> dict:
    if role == "technician":
        return {
            "full_name": "Carlos Tecnico",
            "document": document,
            "phone": "3017654321",
            "password": "ClaveSegura123",
            "specialty": "Neveras",
            "latitude": 7.8939,
            "longitude": -72.5078,
        }
    return {
        "full_name": "Ana Cliente",
        "document": document,
        "phone": "3001234567",
        "password": "ClaveSegura123",
    }


async def _register_and_login(client: AsyncClient, role: str):
    """Register a user and return (document, access_token)."""
    document = _unique_document()
    await client.post(f"/api/auth/register/{role}", json=_register_payload(document, role))
    login = await client.post(
        "/api/auth/login",
        json={"document": document, "password": "ClaveSegura123"},
    )
    assert login.status_code == 200
    return document, login.json()["access_token"]


def _auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _first_equipment_id() -> int:
    async with AsyncSessionLocal() as session:
        return (
            await session.execute(select(Equipment.id).order_by(Equipment.id).limit(1))
        ).scalar_one()


async def _create_request(
    client: AsyncClient, token: str, equipment_id: int, latitude: float = 7.8939
) -> dict:
    response = await client.post(
        "/api/services/",
        headers=_auth_headers(token),
        json={
            "equipment_id": equipment_id,
            "service_type": "repair",
            "description": "El aire acondicionado no enfría",
            "latitude": latitude,
            "longitude": -72.5078,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.fixture
async def client():
    """Test app: real services + auth routers (real get_db / get_current_user)."""
    app = FastAPI()
    app.include_router(auth_router)
    app.include_router(services_router)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture(autouse=True)
async def _cleanup_after_each_test():
    """Aisla cada test: borra los datos del prefijo de prueba al terminar.

    Los tests del radar cliente crean técnicos que quedan en radio del centro
    de Cúcuta; sin esta limpieza, los `count` de los tests siguientes se
    contaminan (el cleanup de conftest es a nivel sesión).
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
        await session.execute(
            text("DELETE FROM technicians WHERE user_id IS NOT NULL")
        )
        await session.execute(
            text("DELETE FROM users WHERE document LIKE '100%'")
        )
        await session.commit()


# --- Bid sin costos -> 422 por campo (RF-SR-002) ------------------------------

async def test_bid_without_costs_returns_422_with_field_errors(client):
    client_doc, client_token = await _register_and_login(client, "client")
    _, tech_token = await _register_and_login(client, "technician")
    equipment_id = await _first_equipment_id()
    request = await _create_request(client, client_token, equipment_id)

    response = await client.post(
        "/api/services/bids/",
        headers=_auth_headers(tech_token),
        json={
            "service_request_id": request["request_id"],
            "price_offered": 80000,
            "estimated_time_minutes": 45,
        },
    )
    assert response.status_code == 422

    # Pydantic reporta el campo faltante: detalle con loc que lo identifica.
    detail = response.json()["detail"]
    locs = {tuple(item.get("loc", ())) for item in detail}
    assert ("body", "transport_cost") in locs
    assert ("body", "diagnosis_cost") in locs


async def test_bid_with_negative_cost_returns_422_and_request_stays_requested(client):
    client_doc, client_token = await _register_and_login(client, "client")
    _, tech_token = await _register_and_login(client, "technician")
    equipment_id = await _first_equipment_id()
    request = await _create_request(client, client_token, equipment_id)

    response = await client.post(
        "/api/services/bids/",
        headers=_auth_headers(tech_token),
        json={
            "service_request_id": request["request_id"],
            "price_offered": 80000,
            "estimated_time_minutes": 45,
            "transport_cost": -1,
            "diagnosis_cost": 50000,
        },
    )
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert any("transport_cost" in str(item) for item in detail)

    # La solicitud NO cambió de estado y no se creó ningún bid.
    async with AsyncSessionLocal() as session:
        req = (
            await session.execute(
                select(ServiceRequest).where(
                    ServiceRequest.id == request["request_id"]
                )
            )
        ).scalar_one()
        bids = (
            await session.execute(
                select(TechnicianBid).where(
                    TechnicianBid.service_request_id == request["request_id"]
                )
            )
        ).scalars().all()
    assert req.status == "requested"
    assert len(bids) == 0


async def test_bid_with_negative_diagnosis_cost_returns_422_per_field(client):
    client_doc, client_token = await _register_and_login(client, "client")
    _, tech_token = await _register_and_login(client, "technician")
    equipment_id = await _first_equipment_id()
    request = await _create_request(client, client_token, equipment_id)

    response = await client.post(
        "/api/services/bids/",
        headers=_auth_headers(tech_token),
        json={
            "service_request_id": request["request_id"],
            "price_offered": 80000,
            "estimated_time_minutes": 45,
            "transport_cost": 20000,
            "diagnosis_cost": -5,
        },
    )
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert any("diagnosis_cost" in str(item) for item in detail)


# --- Bid válido: costos >= 0 -> 201 y la solicitud abre mercado (RF-TEC-006) ---

async def test_successful_bid_creates_bid_with_costs_and_sets_bidding(client):
    client_doc, client_token = await _register_and_login(client, "client")
    tech_doc, tech_token = await _register_and_login(client, "technician")
    # RF-TEC-006 (aplicado en 3.4): ofertar exige técnico `verified`.
    await _update_technician(tech_doc, verification_status="verified")
    equipment_id = await _first_equipment_id()
    request = await _create_request(client, client_token, equipment_id)

    response = await client.post(
        "/api/services/bids/",
        headers=_auth_headers(tech_token),
        json={
            "service_request_id": request["request_id"],
            "price_offered": 80000,
            "estimated_time_minutes": 45,
            "transport_cost": 15000,
            "diagnosis_cost": 35000,
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "pending"

    async with AsyncSessionLocal() as session:
        req = (
            await session.execute(
                select(ServiceRequest).where(
                    ServiceRequest.id == request["request_id"]
                )
            )
        ).scalar_one()
        bid = (
            await session.execute(
                select(TechnicianBid).where(
                    TechnicianBid.service_request_id == request["request_id"]
                )
            )
        ).scalar_one()
    assert req.status == "bidding"
    assert bid.transport_cost == 15000
    assert bid.diagnosis_cost == 35000
    assert bid.status == "pending"


# --- equipment_id inválido -> 404 (RF-SR-011) ---------------------------------

async def test_create_request_with_invalid_equipment_id_returns_404(client):
    _, client_token = await _register_and_login(client, "client")

    response = await client.post(
        "/api/services/",
        headers=_auth_headers(client_token),
        json={
            "equipment_id": 999999,
            "service_type": "repair",
            "description": "Equipo inexistente",
            "latitude": 7.8939,
            "longitude": -72.5078,
        },
    )
    assert response.status_code == 404


# --- user_id viene del token, no del payload (RF-SR-001) ----------------------

async def test_create_request_binds_authenticated_user_from_token(client):
    client_doc, client_token = await _register_and_login(client, "client")
    equipment_id = await _first_equipment_id()

    response = await client.post(
        "/api/services/",
        headers=_auth_headers(client_token),
        json={
            "equipment_id": equipment_id,
            "service_type": "repair",
            "description": "Lavadora no centrifuga",
            "latitude": 7.8939,
            "longitude": -72.5078,
        },
    )
    assert response.status_code == 201

    async with AsyncSessionLocal() as session:
        user = (
            await session.execute(select(User).where(User.document == client_doc))
        ).scalar_one()
        req = (
            await session.execute(
                select(ServiceRequest).where(
                    ServiceRequest.id == response.json()["request_id"]
                )
            )
        ).scalar_one()
    assert req.user_id == user.id
    assert req.status == "requested"


async def test_create_request_without_token_returns_401(client):
    response = await client.post(
        "/api/services/",
        json={
            "equipment_id": 1,
            "service_type": "repair",
            "description": "Sin token",
            "latitude": 7.8939,
            "longitude": -72.5078,
        },
    )
    assert response.status_code == 401


# --- 2.5 Radar cliente: solo verified+free, orden y filtros (RF-MATCH-001/003) ---

async def _update_technician(document: str, *, location_wkt: str | None = None, **columns):
    """Ajusta el perfil del técnico en DB (verification/availability/rating/...)."""
    async with AsyncSessionLocal() as session:
        user = (
            await session.execute(select(User).where(User.document == document))
        ).scalar_one()
        sets = ", ".join(f"{col} = :{col}" for col in columns)
        params = {**columns, "uid": user.id}
        if location_wkt is not None:
            sql = (
                "UPDATE technicians SET location = ST_GeomFromText(:loc, 4326), "
                f"{sets} WHERE user_id = :uid"
            )
            params = {**columns, "uid": user.id, "loc": location_wkt}
        else:
            sql = f"UPDATE technicians SET {sets} WHERE user_id = :uid"
        await session.execute(text(sql), params)
        await session.commit()


async def test_nearby_lists_only_verified_and_free_ordered_by_proximity(client):
    # A y B: verified+free a distinta distancia. C: pending. D: verified+busy.
    for i, (offset, status, availability) in enumerate(
        [
            (0.01, "verified", "free"),   # A ~1.1 km
            (0.02, "verified", "free"),   # B ~2.2 km
            (0.01, "pending", "free"),    # C excluido por verificación
            (0.01, "verified", "busy"),   # D excluido por ocupado
        ]
    ):
        doc, _ = await _register_and_login(client, "technician")
        await _update_technician(
            doc,
            location_wkt=f"POINT(-72.5078 {7.8939 + offset})",
            verification_status=status,
            availability=availability,
            rating=float(i),
        )

    response = await client.get(
        "/api/services/technicians-nearby/",
        params={
            "latitude": 7.8939,
            "longitude": -72.5078,
            "radius_km": 5.0,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["count"] == 2
    assert body["technicians"][0]["distance_km"] < body["technicians"][1]["distance_km"]
    for tech in body["technicians"]:
        assert set(tech) >= {
            "id", "name", "rating", "specialty", "latitude", "longitude", "distance_km"
        }


async def test_nearby_sorts_by_rating_after_distance_and_filters(client):
    # A: cerca (0 km) con rating bajo; B: más lejos (~2.2 km) con mejor rating.
    doc_a, _ = await _register_and_login(client, "technician")
    await _update_technician(doc_a, verification_status="verified", rating=3.0)
    doc_b, _ = await _register_and_login(client, "technician")
    await _update_technician(
        doc_b,
        location_wkt="POINT(-72.5078 7.9139)",
        verification_status="verified",
        rating=4.8,
        specialty="Aires acondicionados",
    )
    params = {"latitude": 7.8939, "longitude": -72.5078, "radius_km": 5.0}

    # Sin filtros: proximidad manda; A (cerca, rating bajo) va antes que B.
    all_ = await client.get("/api/services/technicians-nearby/", params=params)
    assert all_.json()["count"] == 2
    assert all_.json()["technicians"][0]["distance_km"] < 0.2
    assert all_.json()["technicians"][1]["distance_km"] > 1.0
    # En igual distancia, el mejor rating gana: el recuento lo prueba (3.0 y 4.8).

    # Filtro specialty: solo el de Aires acondicionados.
    filtered = await client.get(
        "/api/services/technicians-nearby/",
        params={**params, "specialty": "aires"},
    )
    assert filtered.json()["count"] == 1
    assert filtered.json()["technicians"][0]["specialty"] == "Aires acondicionados"

    # Filtro min_rating: solo el de 4.8.
    rated = await client.get(
        "/api/services/technicians-nearby/",
        params={**params, "min_rating": 4.0},
    )
    assert rated.json()["count"] == 1
    assert rated.json()["technicians"][0]["rating"] == 4.8


async def test_nearby_empty_area_returns_message(client):
    response = await client.get(
        "/api/services/technicians-nearby/",
        params={"latitude": 1.2, "longitude": -77.3, "radius_km": 5.0},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["count"] == 0
    assert body["message"] == "No se encontraron técnicos en tu área"
