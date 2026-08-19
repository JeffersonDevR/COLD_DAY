"""Task 1.1 — RED: integration tests for the auth flow (RF-AUTH-001..008).

Runs against the local PostGIS database (`coldday`). Each test uses a unique
numeric document (prefix `100...`) so sessions never collide; conftest removes
everything this session created.

Harness: a throwaway FastAPI app hosting the REAL auth router plus two
role-guarded dummy endpoints that exercise the REAL `get_current_user` /
`require_roles` dependencies (there are no role-specific endpoints in S1 yet).
"""

import random

import pytest
from fastapi import Depends, FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.api.auth import router as auth_router
from app.api.deps import require_roles
from app.core.database import AsyncSessionLocal
from app.core.security import GENERIC_LOGIN_ERROR
from app.models.service import Technician
from app.models.user import User

pytestmark = pytest.mark.integration


def _unique_document() -> str:
    return f"100{random.randint(10**8, 10**9)}"


def _client_payload(document: str, password: str = "ClaveSegura123") -> dict:
    return {
        "full_name": "Ana Cliente",
        "document": document,
        "phone": "3001234567",
        "password": password,
    }


def _technician_payload(document: str, password: str = "ClaveSegura123") -> dict:
    return {
        "full_name": "Carlos Tecnico",
        "document": document,
        "phone": "3017654321",
        "password": password,
        "specialty": "Neveras",
        "latitude": 7.8939,
        "longitude": -72.5078,
    }


async def _register(client: AsyncClient, path: str, payload: dict):
    return await client.post(f"/api/auth/register/{path}", json=payload)


async def _login(client: AsyncClient, document: str, password: str):
    return await client.post(
        "/api/auth/login",
        json={"document": document, "password": password},
    )


@pytest.fixture
async def client():
    """Test app: real auth router + dummy role-guarded endpoints (real deps)."""
    app = FastAPI()
    app.include_router(auth_router)

    @app.get("/_test/admin-only")
    async def admin_only(user: User = Depends(require_roles("admin"))):
        return {"ok": True}

    @app.get("/_test/client-only")
    async def client_only(user: User = Depends(require_roles("client"))):
        return {"ok": True}

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


# --- Registro de cliente (RF-AUTH-001) -----------------------------------------

async def test_register_client_returns_201_and_creates_client_role(client):
    doc = _unique_document()
    response = await _register(client, "client", _client_payload(doc))
    assert response.status_code == 201
    body = response.json()
    assert body["role"] == "client"
    assert body["document"] == doc

    # The user really exists with a hashed password (no plaintext stored).
    async with AsyncSessionLocal() as session:
        user = (
            await session.execute(select(User).where(User.document == doc))
        ).scalar_one()
    assert user.role == "client"
    assert user.password_hash != _client_payload(doc)["password"]
    assert user.password_hash.startswith("$2b$")


# --- Documento duplicado -> 409 genérico (RF-AUTH-001 escenario) ---------------

async def test_register_duplicate_document_returns_generic_409(client):
    doc = _unique_document()
    first = await _register(client, "client", _client_payload(doc))
    assert first.status_code == 201

    second = await _register(client, "client", _client_payload(doc))
    assert second.status_code == 409
    assert second.json()["detail"] == "No se pudo completar el registro"

    # Only one account exists for that document.
    async with AsyncSessionLocal() as session:
        users = (
            (await session.execute(select(User).where(User.document == doc)))
            .scalars()
            .all()
        )
    assert len(users) == 1


# --- Login sin enumeración (RF-AUTH-003, NFR) ----------------------------------

async def test_login_wrong_password_and_unknown_document_are_identical_401(client):
    doc = _unique_document()
    await _register(client, "client", _client_payload(doc))

    wrong_password = await _login(client, doc, "ContrasenaIncorrecta99")
    unknown_document = await _login(client, _unique_document(), "CualquierClave1")

    assert wrong_password.status_code == 401
    assert unknown_document.status_code == 401
    assert wrong_password.json() == unknown_document.json()
    assert wrong_password.json() == {"detail": GENERIC_LOGIN_ERROR}


# --- Login exitoso (RF-AUTH-003) -------------------------------------------------

async def test_login_success_returns_tokens_role_and_user_id(client):
    doc = _unique_document()
    password = "ClaveSegura123"
    await _register(client, "client", _client_payload(doc, password))

    response = await _login(client, doc, password)
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"access_token", "refresh_token", "role", "user_id"}
    assert body["role"] == "client"
    assert body["user_id"] > 0
    assert len(body["access_token"]) > 20
    assert len(body["refresh_token"]) > 20


# --- Perfil propio: GET / PATCH (RF-AUTH-006) ------------------------------------

async def _auth_headers(client, document, password="ClaveSegura123") -> dict:
    login = await _login(client, document, password)
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


async def test_me_get_returns_own_profile(client):
    doc = _unique_document()
    await _register(client, "client", _client_payload(doc))
    headers = await _auth_headers(client, doc)

    response = await client.get("/api/auth/me", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["full_name"] == "Ana Cliente"
    assert body["document"] == doc
    assert body["phone"] == "3001234567"
    assert body["role"] == "client"


async def test_me_patch_updates_name_and_phone(client):
    doc = _unique_document()
    await _register(client, "client", _client_payload(doc))
    headers = await _auth_headers(client, doc)

    patch = await client.patch(
        "/api/auth/me",
        headers=headers,
        json={"full_name": "Ana María Cliente", "phone": "3009998888"},
    )
    assert patch.status_code == 200
    assert patch.json()["full_name"] == "Ana María Cliente"
    assert patch.json()["phone"] == "3009998888"

    # The change is persisted: a fresh GET returns the new values.
    fetched = await client.get("/api/auth/me", headers=headers)
    assert fetched.status_code == 200
    assert fetched.json()["full_name"] == "Ana María Cliente"
    assert fetched.json()["phone"] == "3009998888"


# --- Refresh (RF-AUTH-003) ---------------------------------------------------------

async def test_refresh_rotates_tokens_and_invalidates_old_refresh(client):
    doc = _unique_document()
    await _register(client, "client", _client_payload(doc))
    login = await _login(client, doc, "ClaveSegura123")
    old_refresh = login.json()["refresh_token"]
    old_access = login.json()["access_token"]

    refresh = await client.post(
        "/api/auth/refresh", json={"refresh_token": old_refresh}
    )
    assert refresh.status_code == 200
    new_body = refresh.json()
    assert new_body["access_token"] != old_access
    assert new_body["refresh_token"] != old_refresh

    # Replaying the already-consumed refresh token is rejected.
    replay = await client.post(
        "/api/auth/refresh", json={"refresh_token": old_refresh}
    )
    assert replay.status_code == 401

    # The new access token actually works.
    me = await client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {new_body['access_token']}"},
    )
    assert me.status_code == 200


# --- Logout revoca el refresh (RF-AUTH-007) -----------------------------------------

async def test_logout_revokes_refresh_token(client):
    doc = _unique_document()
    await _register(client, "client", _client_payload(doc))
    login = await _login(client, doc, "ClaveSegura123")
    refresh_token = login.json()["refresh_token"]

    logout = await client.post(
        "/api/auth/logout", json={"refresh_token": refresh_token}
    )
    assert logout.status_code == 200

    refresh = await client.post(
        "/api/auth/refresh", json={"refresh_token": refresh_token}
    )
    assert refresh.status_code == 401


# --- Registro de técnico (RF-AUTH-002) -------------------------------------------------

async def test_register_technician_creates_pending_technician_profile(client):
    doc = _unique_document()
    response = await _register(client, "technician", _technician_payload(doc))
    assert response.status_code == 201
    assert response.json()["role"] == "technician"

    async with AsyncSessionLocal() as session:
        user = (
            await session.execute(select(User).where(User.document == doc))
        ).scalar_one()
        technician = (
            await session.execute(
                select(Technician).where(Technician.user_id == user.id)
            )
        ).scalar_one()
    assert user.role == "technician"
    assert technician.verification_status == "pending"
    assert technician.availability == "free"
    assert technician.specialty == "Neveras"


# --- Política de contraseña en el endpoint (NFR auth) --------------------------------

async def test_register_with_weak_password_returns_422(client):
    doc = _unique_document()
    payload = _client_payload(doc, password="abc123")
    response = await _register(client, "client", payload)
    assert response.status_code == 422
    # No user was created with the weak password.
    async with AsyncSessionLocal() as session:
        users = (
            (await session.execute(select(User).where(User.document == doc)))
            .scalars()
            .all()
        )
    assert len(users) == 0


# --- RBAC (RF-AUTH-004/005) -----------------------------------------------------------

async def test_rbac_rejects_missing_token_with_401(client):
    response = await client.get("/_test/admin-only")
    assert response.status_code == 401


async def test_rbac_client_token_gets_403_on_admin_only(client):
    doc = _unique_document()
    await _register(client, "client", _client_payload(doc))
    headers = await _auth_headers(client, doc)

    admin_only = await client.get("/_test/admin-only", headers=headers)
    assert admin_only.status_code == 403

    client_only = await client.get("/_test/client-only", headers=headers)
    assert client_only.status_code == 200
    assert client_only.json() == {"ok": True}


async def test_rbac_technician_token_gets_403_on_client_only(client):
    doc = _unique_document()
    await _register(client, "technician", _technician_payload(doc))
    headers = await _auth_headers(client, doc)

    client_only = await client.get("/_test/client-only", headers=headers)
    assert client_only.status_code == 403

    admin_only = await client.get("/_test/admin-only", headers=headers)
    assert admin_only.status_code == 403


async def test_rbac_invalid_token_gets_401(client):
    response = await client.get(
        "/_test/admin-only", headers={"Authorization": "Bearer token-invalido"}
    )
    assert response.status_code == 401