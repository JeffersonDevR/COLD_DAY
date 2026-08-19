"""Dependencias de autenticación y RBAC (S1 mvp-polish, design §Auth).

- get_current_user: HTTPBearer -> decode JWT -> carga el User -> 401 si falla.
- require_roles(*roles): devuelve el User solo si su rol está permitido -> 403.
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import decode_access_token
from app.models.user import User

bearer_scheme = HTTPBearer(auto_error=False)

UNAUTHORIZED_DETAIL = "No autenticado"


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Valida el access token y devuelve el usuario autenticado (401 si no)."""
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=UNAUTHORIZED_DETAIL
        )

    payload = decode_access_token(credentials.credentials)  # 401 si inválido
    try:
        user_id = int(payload["sub"])
    except (KeyError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=UNAUTHORIZED_DETAIL
        )

    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=UNAUTHORIZED_DETAIL
        )
    return user


def require_roles(*roles: str):
    """Factory de dependencia RBAC: solo los roles listados pasan (403 si no)."""

    async def dependency(user: User = Depends(get_current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tienes permisos para esta acción",
            )
        return user

    return dependency