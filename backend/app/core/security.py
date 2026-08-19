"""Security primitives (S1 mvp-polish, design §Auth).

- bcrypt cost 12 via run_in_threadpool (async-friendly, design decision).
- PyJWT access tokens: 24h for client/technician, 4h for admin, role claim.
- Refresh tokens: opaque (secrets), stored hashed with sha256 in auth_tokens.
- Password policy: >= 8 chars with uppercase, lowercase and digit.
- No user enumeration: single generic login-failure message.
"""

import hashlib
import os
import re
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from fastapi import HTTPException, status
from passlib.hash import bcrypt
from starlette.concurrency import run_in_threadpool

BCRYPT_ROUNDS = 12
ACCESS_TOKEN_LIFETIME = timedelta(hours=24)  # client / technician (RF-AUTH-003)
ADMIN_TOKEN_LIFETIME = timedelta(hours=4)  # admin sessions <= 4h (RF-AUTH-003)
REFRESH_TOKEN_LIFETIME = timedelta(days=30)

JWT_ALGORITHM = "HS256"
# >= 32 bytes para HS256 (RFC 7518). Clave de desarrollo; en producción
# COLDDAY_JWT_SECRET debe venir del entorno.
JWT_SECRET = os.environ.get(
    "COLDDAY_JWT_SECRET", "coldday-dev-secret-change-me-0123456789abcdef"
)

# Mensaje único para login fallido: mismo para CC inexistente y contraseña
# incorrecta (NFR auth — sin enumeración de usuarios).
GENERIC_LOGIN_ERROR = "Credenciales inválidas"
GENERIC_REGISTER_ERROR = "No se pudo completar el registro"


# --- Password policy (NFR auth) -----------------------------------------------

def password_policy_errors(password: str) -> list[str]:
    """Devuelve los errores de la política; lista vacía = contraseña válida.

    Política: >= 8 caracteres con mayúscula, minúscula y dígito.
    """
    errors: list[str] = []
    if len(password) < 8:
        errors.append("La contraseña debe tener al menos 8 caracteres.")
    if not re.search(r"[A-Z]", password):
        errors.append("La contraseña debe incluir al menos una letra mayúscula.")
    if not re.search(r"[a-z]", password):
        errors.append("La contraseña debe incluir al menos una letra minúscula.")
    if not re.search(r"\d", password):
        errors.append("La contraseña debe incluir al menos un dígito.")
    return errors


# --- Password hashing (bcrypt cost 12, async via threadpool) --------------------

def _hash_password_sync(password: str) -> str:
    return bcrypt.using(rounds=BCRYPT_ROUNDS).hash(password)


async def hash_password(password: str) -> str:
    return await run_in_threadpool(_hash_password_sync, password)


def _verify_password_sync(password: str, password_hash: str) -> bool:
    return bcrypt.verify(password, password_hash)


async def verify_password(password: str, password_hash: str) -> bool:
    return await run_in_threadpool(_verify_password_sync, password, password_hash)


# --- JWT access tokens (design §Auth) -------------------------------------------

def create_access_token(user_id: int, role: str) -> str:
    """Access token con claim de rol; 24h salvo admin (4h).

    Incluye `jti` (id único) para que cada token sea distinguible aunque se
    acuñe dentro del mismo segundo (el iat de JWT tiene resolución de 1s).
    """
    lifetime = ADMIN_TOKEN_LIFETIME if role == "admin" else ACCESS_TOKEN_LIFETIME
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": str(user_id),
        "role": role,
        "jti": secrets.token_urlsafe(16),
        "iat": now,
        "exp": now + lifetime,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> dict[str, Any]:
    """Decodifica y valida el access token; 401 si inválido o expirado."""
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesión inválida o expirada",
        )


# --- Refresh tokens (opacos, hasheados en DB) --------------------------------------

def generate_refresh_token() -> str:
    """Refresh opaco de alta entropía; nunca se guarda en claro."""
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
    """Hash sha256 hex con el que se persiste/busca el refresh en auth_tokens."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def refresh_token_expires_at() -> datetime:
    return datetime.now(timezone.utc) + REFRESH_TOKEN_LIFETIME