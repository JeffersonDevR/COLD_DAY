"""Endpoints de autenticación (S1 mvp-polish, RF-AUTH-001..008).

- POST /api/auth/register/client        -> 201, rol client (RF-AUTH-001)
- POST /api/auth/register/technician    -> 201, User technician + Technician pending
- POST /api/auth/login                  -> tokens; 401 genérico (RF-AUTH-003, NFR)
- POST /api/auth/refresh                -> rota refresh + access (RF-AUTH-003)
- POST /api/auth/logout                 -> revoca el refresh (RF-AUTH-007)
- GET/PATCH /api/auth/me                -> perfil propio (RF-AUTH-006)
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.security import (
    GENERIC_LOGIN_ERROR,
    GENERIC_REGISTER_ERROR,
    create_access_token,
    generate_refresh_token,
    hash_password,
    hash_refresh_token,
    password_policy_errors,
    refresh_token_expires_at,
    verify_password,
)
from app.models.service import Technician
from app.models.user import AuthToken, User
from app.schemas.auth import (
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterClient,
    RegisterTechnician,
    TokenResponse,
    UserOut,
    UserUpdate,
)

router = APIRouter(prefix="/api/auth", tags=["Auth"])


async def _create_refresh_token(db: AsyncSession, user_id: int) -> str:
    """Genera un refresh opaco, lo persiste hasheado y devuelve el token en claro."""
    token = generate_refresh_token()
    db.add(
        AuthToken(
            user_id=user_id,
            token_hash=hash_refresh_token(token),
            expires_at=refresh_token_expires_at(),
        )
    )
    await db.commit()
    return token


async def _issue_token_pair(db: AsyncSession, user: User) -> TokenResponse:
    access = create_access_token(user.id, user.role)
    refresh = await _create_refresh_token(db, user.id)
    return TokenResponse(
        access_token=access, refresh_token=refresh, role=user.role, user_id=user.id
    )


async def _register_user(
    db: AsyncSession,
    *,
    full_name: str,
    document: str,
    phone: str,
    password: str,
    role: str,
) -> User:
    # Política de contraseña -> 422 con los errores por campo (NFR auth).
    policy_errors = password_policy_errors(password)
    if policy_errors:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=policy_errors,
        )

    # Duplicado -> 409 genérico (sin revelar que la cuenta existe).
    existing = (
        await db.execute(select(User).where(User.document == document))
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=GENERIC_REGISTER_ERROR
        )

    user = User(
        full_name=full_name,
        document=document,
        phone=phone,
        password_hash=await hash_password(password),
        role=role,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/register/client", status_code=status.HTTP_201_CREATED)
async def register_client(
    payload: RegisterClient, db: AsyncSession = Depends(get_db)
) -> UserOut:
    """Registro de cliente: crea un User con rol client (RF-AUTH-001)."""
    user = await _register_user(
        db,
        full_name=payload.full_name,
        document=payload.document,
        phone=payload.phone,
        password=payload.password,
        role="client",
    )
    return UserOut.model_validate(user)


@router.post("/register/technician", status_code=status.HTTP_201_CREATED)
async def register_technician(
    payload: RegisterTechnician, db: AsyncSession = Depends(get_db)
) -> UserOut:
    """Registro de técnico: User rol technician + perfil Technician `pending`
    (RF-AUTH-002). El técnico queda a la espera de verificación del admin."""
    user = await _register_user(
        db,
        full_name=payload.full_name,
        document=payload.document,
        phone=payload.phone,
        password=payload.password,
        role="technician",
    )
    point_wkt = f"POINT({payload.longitude} {payload.latitude})"
    db.add(
        Technician(
            user_id=user.id,
            name=payload.full_name,
            specialty=payload.specialty,
            location=point_wkt,
            verification_status="pending",
            availability="free",
        )
    )
    await db.commit()
    return UserOut.model_validate(user)


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Login por documento + contraseña.

    401 IDÉNTICO para CC inexistente y contraseña incorrecta (NFR auth — sin
    enumeración de usuarios).
    """
    user = (
        await db.execute(select(User).where(User.document == payload.document))
    ).scalar_one_or_none()

    password_ok = (
        await verify_password(payload.password, user.password_hash)
        if user is not None
        else False
    )
    if user is None or not password_ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=GENERIC_LOGIN_ERROR
        )

    return await _issue_token_pair(db, user)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(payload: RefreshRequest, db: AsyncSession = Depends(get_db)):
    """Rota el par de tokens: consume el refresh actual y emite uno nuevo.

    Refresh revocado (logout) o ya consumido -> 401 (RF-AUTH-007).
    """
    token_hash = hash_refresh_token(payload.refresh_token)
    auth_token = (
        await db.execute(select(AuthToken).where(AuthToken.token_hash == token_hash))
    ).scalar_one_or_none()

    now = datetime.now(timezone.utc)
    if (
        auth_token is None
        or auth_token.revoked_at is not None
        or auth_token.expires_at.replace(tzinfo=timezone.utc) < now
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=GENERIC_LOGIN_ERROR
        )

    # Consumir el refresh anterior (rotación) y emitir el par nuevo.
    auth_token.revoked_at = now
    await db.commit()

    user = await db.get(User, auth_token.user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=GENERIC_LOGIN_ERROR
        )
    return await _issue_token_pair(db, user)


@router.post("/logout")
async def logout(payload: LogoutRequest, db: AsyncSession = Depends(get_db)):
    """Revoca el refresh token (RF-AUTH-007). Idempotente: revocar algo ya
    revocado o inexistente no es un error."""
    token_hash = hash_refresh_token(payload.refresh_token)
    auth_token = (
        await db.execute(select(AuthToken).where(AuthToken.token_hash == token_hash))
    ).scalar_one_or_none()
    if auth_token is not None and auth_token.revoked_at is None:
        auth_token.revoked_at = datetime.now(timezone.utc)
        await db.commit()
    return {"message": "Sesión cerrada"}


@router.get("/me", response_model=UserOut)
async def get_me(user: User = Depends(get_current_user)) -> UserOut:
    """Perfil del usuario autenticado (RF-AUTH-006)."""
    return UserOut.model_validate(user)


@router.patch("/me", response_model=UserOut)
async def update_me(
    payload: UserUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserOut:
    """Actualiza nombre / teléfono del propio perfil (RF-AUTH-006)."""
    if payload.full_name is not None:
        user.full_name = payload.full_name
    if payload.phone is not None:
        user.phone = payload.phone
    await db.commit()
    await db.refresh(user)
    return UserOut.model_validate(user)