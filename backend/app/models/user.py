"""Auth models: users and revocable refresh tokens (S1 mvp-polish).

Design decisions enforced here: document unique (CC), role client/technician/
admin, refresh token stored only as its sha256 hash (never the raw token).
"""

from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import relationship

from app.core.database import Base


class User(Base):
    """Usuario de la plataforma: cliente, técnico o administrador.

    El documento (CC) es único; el login se hace con documento + contraseña
    (sin email obligatorio, decisión del piloto).
    """

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(100), nullable=False)
    document = Column(String(20), nullable=False, unique=True, index=True)
    phone = Column(String(30), nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(
        String(20), nullable=False, default="client"
    )  # "client" | "technician" | "admin"
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    auth_tokens = relationship(
        "AuthToken", back_populates="user", cascade="all, delete"
    )


class AuthToken(Base):
    """Refresh token revocable; en DB solo se guarda el hash sha256.

    logout marca revoked_at, refresh rotado consume el token anterior
    (RF-AUTH-007).
    """

    __tablename__ = "auth_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    token_hash = Column(String(64), nullable=False, unique=True, index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    revoked_at = Column(DateTime(timezone=True), nullable=True)

    user = relationship("User", back_populates="auth_tokens")