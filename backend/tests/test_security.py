"""Task 1.2 — RED: unit tests for auth primitives.

- Password policy: >= 8 chars with upper, lower and digit (spec NFR auth).
- No user enumeration: a single generic login-failure message that the login
  endpoint MUST use for both failure branches (unknown CC / wrong password).
- JWT access tokens: 24h for client/technician, 4h for admin, claims with role.
- Refresh tokens: opaque, stored hashed with sha256.

No DB required: everything here is a pure function / library call.
"""

import hashlib
from datetime import timedelta

import jwt as pyjwt

from app.core.security import (
    ADMIN_TOKEN_LIFETIME,
    ACCESS_TOKEN_LIFETIME,
    GENERIC_LOGIN_ERROR,
    JWT_ALGORITHM,
    JWT_SECRET,
    create_access_token,
    generate_refresh_token,
    hash_refresh_token,
    password_policy_errors,
)


# --- Password policy ---------------------------------------------------------

def test_password_policy_accepts_valid_password():
    errors = password_policy_errors("ClaveSegura123")
    assert errors == []


def test_password_policy_rejects_short_password():
    errors = password_policy_errors("A1c")
    assert errors == ["La contraseña debe tener al menos 8 caracteres."]


def test_password_policy_rejects_password_without_uppercase():
    errors = password_policy_errors("clavesegura123")
    assert errors == ["La contraseña debe incluir al menos una letra mayúscula."]


def test_password_policy_rejects_password_without_lowercase():
    errors = password_policy_errors("CLAVESEGURA123")
    assert errors == ["La contraseña debe incluir al menos una letra minúscula."]


def test_password_policy_rejects_password_without_digit():
    errors = password_policy_errors("Clavesegura")
    assert errors == ["La contraseña debe incluir al menos un dígito."]


def test_password_policy_reports_every_violation_at_once():
    errors = password_policy_errors("abc")
    assert errors == [
        "La contraseña debe tener al menos 8 caracteres.",
        "La contraseña debe incluir al menos una letra mayúscula.",
        "La contraseña debe incluir al menos un dígito.",
    ]


# --- No user enumeration ------------------------------------------------------

def test_login_failure_message_is_single_generic_constant():
    # Both branches of the login endpoint (CC inexistente / contraseña mala)
    # MUST raise this exact message, so the API never reveals whether a CC
    # is registered. The integration suite asserts both 401 bodies equal it.
    assert GENERIC_LOGIN_ERROR == "Credenciales inválidas"


# --- JWT access tokens ---------------------------------------------------------

def test_client_access_token_lifetime_is_24h_with_role_claim():
    token = create_access_token(user_id=42, role="client")
    payload = pyjwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    assert payload["sub"] == "42"
    assert payload["role"] == "client"
    assert payload["exp"] - payload["iat"] == int(
        ACCESS_TOKEN_LIFETIME.total_seconds()
    )
    assert int(ACCESS_TOKEN_LIFETIME.total_seconds()) == 24 * 3600


def test_admin_access_token_lifetime_is_4h_with_role_claim():
    token = create_access_token(user_id=1, role="admin")
    payload = pyjwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    assert payload["sub"] == "1"
    assert payload["role"] == "admin"
    assert payload["exp"] - payload["iat"] == int(
        ADMIN_TOKEN_LIFETIME.total_seconds()
    )
    assert int(ADMIN_TOKEN_LIFETIME.total_seconds()) == 4 * 3600


def test_access_token_lifetime_configuration_values():
    assert ACCESS_TOKEN_LIFETIME == timedelta(hours=24)
    assert ADMIN_TOKEN_LIFETIME == timedelta(hours=4)


# --- Refresh tokens ------------------------------------------------------------

def test_refresh_token_is_opaque_and_hashed_with_sha256():
    token = generate_refresh_token()
    h = hash_refresh_token(token)
    assert h == hashlib.sha256(token.encode("utf-8")).hexdigest()
    assert len(h) == 64


def test_refresh_token_hash_is_deterministic_and_distinct():
    first = generate_refresh_token()
    second = generate_refresh_token()
    assert first != second
    assert hash_refresh_token(first) != hash_refresh_token(second)
    assert hash_refresh_token(first) == hash_refresh_token(first)