"""Tasks 2.3/2.4 — RED: technician radar serialization (RF-MATCH-004/005).

The baseline `GET /api/technicians/requests/nearby/` serializes raw ORM rows
(500) and never filters by status. The fixed contract:
- returns a JSON DTO per request: id, equipment, description, latitude,
  longitude, status (no 500, Geometry exposed as lat/lng);
- lists only `requested`/`bidding` requests inside the radius;
- requests the technician already bid on show the bid status (`my_bid_status`)
  instead of being offered again;
- requires a `verified` technician (token-based): pending -> 403.

Harness: throwaway FastAPI app with the REAL technicians + auth + services
routers against the local PostGIS database.
"""

import random

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text

from app.api.auth import router as auth_router
from app.api.services import router as services_router
from app.api.technicians import router as technicians_router
from app.core.database import AsyncSessionLocal
from app.models.service import Equipment, ServiceRequest
from app.models.user import User

pytestmark = pytest.mark.integration

CUCUTA_LAT, CUCUTA_LON = 7.8939, -72.5078


def _unique_document() -> str:
    return f"100{random.randint(10**8, 10**9)}"


async def _register_and_login(client: AsyncClient, role: str):
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


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _set_verification(document: str, status: str) -> int:
    """Flips the technician profile status and returns its technician.id."""
    async with AsyncSessionLocal() as session:
        user = (
            await session.execute(select(User).where(User.document == document))
        ).scalar_one()
        await session.execute(
            text("UPDATE technicians SET verification_status = :s WHERE user_id = :u"),
            {"s": status, "u": user.id},
        )
        await session.commit()
        tech_id = (
            await session.execute(
                text("SELECT id FROM technicians WHERE user_id = :u"),
                {"u": user.id},
            )
        ).scalar_one()
    return tech_id


async def _create_request(
    client: AsyncClient, token: str, *, description: str, lat: float = CUCUTA_LAT
) -> int:
    async with AsyncSessionLocal() as session:
        equipment_id = (
            await session.execute(
                select(Equipment.id).order_by(Equipment.id).limit(1)
            )
        ).scalar_one()
    response = await client.post(
        "/api/services/",
        headers=_auth(token),
        json={
            "equipment_id": equipment_id,
            "service_type": "repair",
            "description": description,
            "latitude": lat,
            "longitude": CUCUTA_LON,
        },
    )
    assert response.status_code == 201
    return response.json()["request_id"]


async def _set_status(request_id: int, status: str):
    async with AsyncSessionLocal() as session:
        req = await session.get(ServiceRequest, request_id)
        req.status = status
        await session.commit()


@pytest.fixture
async def client():
    app = FastAPI()
    app.include_router(auth_router)
    app.include_router(services_router)
    app.include_router(technicians_router)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


async def test_radar_returns_serialized_dto_only_for_requested_and_bidding(client):
    _, client_token = await _register_and_login(client, "client")
    tech_doc, tech_token = await _register_and_login(client, "technician")
    await _set_verification(tech_doc, "verified")

    near_id = await _create_request(
        client, client_token, description="Nevera no enfria"
    )
    bidding_id = await _create_request(
        client, client_token, description="Aire sin gas"
    )
    await _set_status(bidding_id, "bidding")
    completed_id = await _create_request(
        client, client_token, description="Ya terminada"
    )
    await _set_status(completed_id, "completed")
    cancelled_id = await _create_request(
        client, client_token, description="Cancelada"
    )
    await _set_status(cancelled_id, "cancelled")

    response = await client.get(
        "/api/technicians/requests/nearby/", headers=_auth(tech_token)
    )
    assert response.status_code == 200

    requests = response.json()["requests"]
    ids = {item["id"] for item in requests}
    assert near_id in ids
    assert bidding_id in ids
    assert completed_id not in ids
    assert cancelled_id not in ids

    # DTO completo: id, equipo, descripción, lat/lng y status (sin 500).
    by_id = {item["id"]: item for item in requests}
    near = by_id[near_id]
    assert near["equipment"]
    assert near["description"] == "Nevera no enfria"
    assert abs(near["latitude"] - CUCUTA_LAT) < 1e-6
    assert abs(near["longitude"] - CUCUTA_LON) < 1e-6
    assert near["status"] == "requested"
    assert "my_bid_status" in near
    assert near["my_bid_status"] is None


async def test_radar_excludes_out_of_radius_requests(client):
    _, client_token = await _register_and_login(client, "client")
    tech_doc, tech_token = await _register_and_login(client, "technician")
    await _set_verification(tech_doc, "verified")

    # ~2.4 grados al norte (~267 km): fuera del radio de 10 km.
    far_id = await _create_request(
        client, client_token, description="Lejísimos", lat=CUCUTA_LAT + 2.4
    )

    response = await client.get(
        "/api/technicians/requests/nearby/", headers=_auth(tech_token)
    )
    assert response.status_code == 200
    ids = {item["id"] for item in response.json()["requests"]}
    assert far_id not in ids


async def test_radar_shows_bid_status_for_already_bid_request(client):
    _, client_token = await _register_and_login(client, "client")
    tech_doc, tech_token = await _register_and_login(client, "technician")
    await _set_verification(tech_doc, "verified")

    request_id = await _create_request(
        client, client_token, description="Ya ofertada"
    )
    bid = await client.post(
        "/api/services/bids/",
        headers=_auth(tech_token),
        json={
            "service_request_id": request_id,
            "price_offered": 80000,
            "estimated_time_minutes": 45,
            "transport_cost": 15000,
            "diagnosis_cost": 35000,
        },
    )
    assert bid.status_code == 201

    response = await client.get(
        "/api/technicians/requests/nearby/", headers=_auth(tech_token)
    )
    assert response.status_code == 200
    by_id = {item["id"]: item for item in response.json()["requests"]}
    assert by_id[request_id]["my_bid_status"] == "pending"


async def test_radar_requires_verified_technician(client):
    # Técnico pendiente (estado por defecto del registro, RF-AUTH-002).
    _, tech_token = await _register_and_login(client, "technician")

    response = await client.get(
        "/api/technicians/requests/nearby/", headers=_auth(tech_token)
    )
    assert response.status_code == 403