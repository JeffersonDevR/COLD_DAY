"""Task 4.1 — RED: ratings post-servicio (RF-RAT-001..006).

Integration contra PostGIS local (mismo harness que test_pacto_flow.py): routers
REALES auth + services. Escenarios de la spec §5 ratings:

- Evaluación exitosa y recálculo: global 4.7 (5/4/5 -> 14/3 redondeado a 1
  decimal) + Technician.rating recalculado (RF-RAT-003/005);
- Evaluación duplicada: segunda evaluación sobre la misma solicitud -> 409
  (constraint único por request, RF-RAT-004);
- Evaluación sobre solicitud no completada -> 422 (RF-RAT-001/006);
- Comentario que excede el límite (>1000) -> 422 (RF-RAT-002);
- Evaluación ajena: otro cliente (no dueño) o el técnico -> 403 (RF-RAT-001).

Referencia POST /api/services/{id}/review/ y el modelo Review, que no existen
todavía -> RED garantizado.
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
    Review,
    ServiceRequest,
    Technician,
)

pytestmark = pytest.mark.integration

CUCUTA_LAT, CUCUTA_LON = 7.8939, -72.5078


def _unique_document() -> str:
    return f"100{random.randint(10**8, 10**9)}"


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


async def _register_verified_technician(client: AsyncClient):
    """Registra un técnico y lo pasa a `verified`.

    Returns (document, access_token, technician_id).
    """
    document, token = await _register_and_login(client, "technician")
    from app.models.user import User

    async with AsyncSessionLocal() as session:
        # El perfil se crea en el registro; localizarlo por documento del User.
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


async def _create_bid(client: AsyncClient, tech_token: str, request_id: int) -> int:
    response = await client.post(
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
    assert response.status_code == 201, response.text
    return response.json()["bid_id"]


async def _walk_to_completed(
    client: AsyncClient, client_token: str, tech_token: str, request_id: int
) -> None:
    """Recorre el ciclo feliz completo: oferta -> ... -> completed (RF-SR-003..008)."""
    bid_id = await _create_bid(client, tech_token, request_id)
    accept = await client.post(
        f"/api/services/{request_id}/bids/{bid_id}/accept",
        headers=_auth(client_token),
    )
    assert accept.status_code == 200, accept.text
    diag = await client.post(
        f"/api/services/{request_id}/diagnosis",
        headers=_auth(tech_token),
        json={"observations": "Fuga de gas en la línea de alta"},
    )
    assert diag.status_code == 200, diag.text
    pact = await client.post(
        f"/api/services/{request_id}/agreements/",
        headers=_auth(tech_token),
        json={
            "labor_cost": 80000,
            "transport_cost": 15000,
            "diagnosis_cost": 35000,
            "observations": "Fuga de gas en la línea de alta",
        },
    )
    assert pact.status_code == 201, pact.text
    agreement_id = pact.json()["agreement_id"]
    accept_pact = await client.post(
        f"/api/services/{request_id}/agreements/{agreement_id}/accept",
        headers=_auth(client_token),
    )
    assert accept_pact.status_code == 200, accept_pact.text
    done = await client.post(
        f"/api/services/{request_id}/complete", headers=_auth(tech_token)
    )
    assert done.status_code == 200, done.text


async def _post_review(
    client: AsyncClient,
    token: str,
    request_id: int,
    *,
    punctuality: int = 5,
    quality: int = 4,
    professionalism: int = 5,
    comment: str | None = "Excelente servicio, muy puntual",
):
    return await client.post(
        f"/api/services/{request_id}/review/",
        headers=_auth(token),
        json={
            "punctuality": punctuality,
            "quality": quality,
            "professionalism": professionalism,
            "comment": comment,
        },
    )


async def _review_row(request_id: int) -> Review:
    async with AsyncSessionLocal() as session:
        return (
            await session.execute(
                select(Review).where(Review.service_request_id == request_id)
            )
        ).scalar_one()


async def _technician_rating(technician_id: int) -> float:
    async with AsyncSessionLocal() as session:
        tech = await session.get(Technician, technician_id)
        return tech.rating


@pytest.fixture
async def client():
    """App de tests: routers reales auth + services (get_db / get_current_user reales)."""
    app = FastAPI()
    app.include_router(auth_router)
    app.include_router(services_router)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture(autouse=True)
async def _cleanup_after_each_test():
    """Aísla cada test: borra todo lo creado con documentos de prueba '100...'.

    Orden de FK: reviews -> agreements -> bids -> requests -> technicians -> users.
    El guard de tabla cubre la fase RED (la tabla `reviews` aún no existe).
    """
    yield
    async with AsyncSessionLocal() as session:
        has_reviews = (
            await session.execute(text("SELECT to_regclass('public.reviews')"))
        ).scalar()
        if has_reviews is not None:
            await session.execute(
                text(
                    "DELETE FROM reviews WHERE service_request_id IN "
                    f"(SELECT id FROM service_requests WHERE user_id IN "
                    f"(SELECT id FROM users WHERE document LIKE '100%'))"
                )
            )
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


# --- Escenario: Evaluación exitosa y recálculo (RF-RAT-003/005) ---------------

async def test_successful_review_global_4_7_and_rating_recalc(client):
    """puntualidad 5, calidad 4, profesionalismo 5 -> global 4.7 (1 decimal);

    Technician.rating se recalcula al nuevo promedio (única evaluación -> 4.7).
    """
    _, client_token = await _register_and_login(client, "client")
    _, tech_token, tech_id = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)
    await _walk_to_completed(client, client_token, tech_token, request_id)

    resp = await _post_review(client, client_token, request_id)
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["global_score"] == 4.7
    assert body["technician_rating"] == 4.7

    # La fila Review persiste con los datos correctos (RF-RAT-002).
    review = await _review_row(request_id)
    assert review.punctuality == 5
    assert review.quality == 4
    assert review.professionalism == 5
    assert review.comment == "Excelente servicio, muy puntual"
    assert review.global_score == 4.7
    assert review.technician_id == tech_id

    # El rating del técnico quedó recalculado en DB (RF-RAT-005).
    assert await _technician_rating(tech_id) == 4.7


async def test_rating_recalculates_as_average_of_globals(client):
    """Dos evaluaciones al MISMO técnico: rating = promedio de los globales (1 decimal).

    Review 1 (5/5/5) -> global 5.0; Review 2 (4/4/4) -> global 4.0.
    Technician.rating = (5.0 + 4.0) / 2 = 4.5.
    """
    _, client_token = await _register_and_login(client, "client")
    _, tech_token, tech_id = await _register_verified_technician(client)

    request_1 = await _create_request(client, client_token, description="Nevera 1")
    await _walk_to_completed(client, client_token, tech_token, request_1)
    first = await _post_review(
        client,
        client_token,
        request_1,
        punctuality=5,
        quality=5,
        professionalism=5,
        comment="Perfecto",
    )
    assert first.status_code == 201
    assert first.json()["global_score"] == 5.0
    assert await _technician_rating(tech_id) == 5.0

    request_2 = await _create_request(client, client_token, description="Nevera 2")
    await _walk_to_completed(client, client_token, tech_token, request_2)
    second = await _post_review(
        client,
        client_token,
        request_2,
        punctuality=4,
        quality=4,
        professionalism=4,
        comment="Bien",
    )
    assert second.status_code == 201
    assert second.json()["global_score"] == 4.0
    assert await _technician_rating(tech_id) == 4.5


# --- Escenario: Evaluación duplicada (RF-RAT-004) -----------------------------

async def test_duplicate_review_returns_409(client):
    _, client_token = await _register_and_login(client, "client")
    _, tech_token, tech_id = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)
    await _walk_to_completed(client, client_token, tech_token, request_id)

    first = await _post_review(client, client_token, request_id)
    assert first.status_code == 201

    again = await _post_review(client, client_token, request_id)
    assert again.status_code == 409

    # Sigue existiendo EXACTAMENTE una evaluación para la solicitud.
    async with AsyncSessionLocal() as session:
        count = (
            await session.execute(
                select(Review).where(Review.service_request_id == request_id)
            )
        ).scalars().all()
        assert len(count) == 1
        assert count[0].global_score == 4.7


# --- Escenario: Evaluación sobre solicitud no completada (RF-RAT-001/006) -----

async def test_review_on_non_completed_request_returns_422(client):
    """Solicitud en `in_progress` (no terminada): evaluar -> 422."""
    _, client_token = await _register_and_login(client, "client")
    _, tech_token, _ = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)

    # Llevar hasta in_progress sin completar (mensaje 422: no está completado).
    bid_id = await _create_bid(client, tech_token, request_id)
    assert (
        await client.post(
            f"/api/services/{request_id}/bids/{bid_id}/accept",
            headers=_auth(client_token),
        )
    ).status_code == 200
    assert (
        await client.post(
            f"/api/services/{request_id}/diagnosis",
            headers=_auth(tech_token),
            json={"observations": "Revisión en curso"},
        )
    ).status_code == 200
    pact = await client.post(
        f"/api/services/{request_id}/agreements/",
        headers=_auth(tech_token),
        json={
            "labor_cost": 80000,
            "transport_cost": 15000,
            "diagnosis_cost": 35000,
            "observations": "Revisión en curso",
        },
    )
    agreement_id = pact.json()["agreement_id"]
    assert (
        await client.post(
            f"/api/services/{request_id}/agreements/{agreement_id}/accept",
            headers=_auth(client_token),
        )
    ).status_code == 200

    resp = await _post_review(client, client_token, request_id)
    assert resp.status_code == 422


# --- Escenario: Comentario excede el límite (RF-RAT-002) ----------------------

async def test_comment_over_1000_chars_returns_422(client):
    _, client_token = await _register_and_login(client, "client")
    _, tech_token, _ = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token)
    await _walk_to_completed(client, client_token, tech_token, request_id)

    long_comment = "a" * 1200  # escenario: comentario de 1200 caracteres
    resp = await _post_review(client, client_token, request_id, comment=long_comment)
    assert resp.status_code == 422

    # No se creó ninguna evaluación.
    async with AsyncSessionLocal() as session:
        count = (
            await session.execute(
                select(Review).where(Review.service_request_id == request_id)
            )
        ).scalars().all()
        assert len(count) == 0


# --- Escenario: Evaluación ajena (RF-RAT-001) ---------------------------------

async def test_foreign_client_and_technician_cannot_review(client):
    """Cliente A dueño de la solicitud completada.

    Cliente B (ajeno) -> 403; el técnico asignado -> 403 (rol client requerido).
    """
    _, client_token_a = await _register_and_login(client, "client")
    _, tech_token, tech_id = await _register_verified_technician(client)
    request_id = await _create_request(client, client_token_a)
    await _walk_to_completed(client, client_token_a, tech_token, request_id)

    # Cliente B no es el dueño -> 403.
    _, client_token_b = await _register_and_login(client, "client")
    foreign = await _post_review(client, client_token_b, request_id)
    assert foreign.status_code == 403

    # El técnico asignado tampoco puede evaluar (solo el cliente dueño) -> 403.
    tech_review = await _post_review(client, tech_token, request_id)
    assert tech_review.status_code == 403

    # Sin token -> 401 (get_current_user).
    anon = await client.post(f"/api/services/{request_id}/review/", json={})
    assert anon.status_code == 401

    # Solicitud inexistente -> 404.
    missing = await _post_review(client, client_token_a, request_id=999999)
    assert missing.status_code == 404

    assert await _technician_rating(tech_id) == 0.0  # nada se recalculó