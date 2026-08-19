#!/usr/bin/env python3
"""Seed idempotente del admin piloto (S1 mvp-polish, RF-AUTH-008 parcial).

Crea el usuario admin si no existe (document único). Re-ejecutable sin
duplicar. El seed completo 5 clientes + 5 técnicos + 1 admin llega en S6
(scripts/seed_pilot.py con teardown).

Uso: cd backend && .venv/bin/python scripts/seed_admin.py
"""

import asyncio
import os

from sqlalchemy import select

from app.core.database import AsyncSessionLocal, Base, engine
from app.core.security import hash_password
from app.models.user import User  # noqa: F401  (registra la tabla en create_all)
from app.models import service as _service_models  # noqa: F401


async def seed_admin() -> str:
    admin_document = os.environ.get("COLDDAY_ADMIN_DOCUMENT", "1000000001")
    admin_password = os.environ.get("COLDDAY_ADMIN_PASSWORD", "AdminPiloto123")
    admin_name = os.environ.get("COLDDAY_ADMIN_NAME", "Administrador ColdDay")

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with AsyncSessionLocal() as session:
        existing = (
            await session.execute(
                select(User).where(User.document == admin_document)
            )
        ).scalar_one_or_none()
        if existing is not None:
            return f"Admin ya existía (documento {admin_document}) — sin cambios."

        session.add(
            User(
                full_name=admin_name,
                document=admin_document,
                phone="3000000000",
                password_hash=await hash_password(admin_password),
                role="admin",
            )
        )
        await session.commit()
        return f"Admin creado (documento {admin_document}, rol admin)."


if __name__ == "__main__":
    print(asyncio.run(seed_admin()))