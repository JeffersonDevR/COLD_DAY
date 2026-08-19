"""Task 6.5 — integración: seed piloto idempotente (RF-AUTH-008, RF-PILOT-003).

Contrato verificado sobre la DB real (migrada a alembic head):
  1. seed_pilot() crea exactamente 5 clientes + 5 técnicos (pending) + 1 admin.
  2. Una segunda corrida NO duplica nada (creados=0, existentes completos).
  3. teardown_pilot() elimina solo los documentos del seed, en orden FK.

El test se auto-limpia: arranca con teardown y termina dejando el seed
canónico en pie (mismo estado que una corrida CLI exitosa).
"""

import pytest
from sqlalchemy import func, select

from app.core.database import AsyncSessionLocal
from app.models.service import Technician
from app.models.user import User
from scripts.seed_pilot import (
    ADMIN_DOC,
    CLIENT_DOCS,
    TECHNICIAN_DOCS,
    seed_pilot,
    teardown_pilot,
)

pytestmark = pytest.mark.integration

SEED_DOCS = [*CLIENT_DOCS, *TECHNICIAN_DOCS, ADMIN_DOC]


async def _user_count(*docs: str) -> int:
    async with AsyncSessionLocal() as session:
        return (
            await session.execute(select(func.count(User.id)).where(User.document.in_(docs)))
        ).scalar_one()


async def _technician_count() -> int:
    async with AsyncSessionLocal() as session:
        return (
            await session.execute(
                select(func.count(Technician.id)).where(
                    Technician.user_id.in_(select(User.id).where(User.document.in_(TECHNICIAN_DOCS)))
                )
            )
        ).scalar_one()


async def test_seed_pilot_creates_exact_pilot_shape():
    await teardown_pilot()  # estado limpio, idempotente

    summary = await seed_pilot()

    assert summary.clients_created == 5
    assert summary.technicians_created == 5
    assert summary.admin_created == 1
    assert await _user_count(*CLIENT_DOCS) == 5
    assert await _user_count(*TECHNICIAN_DOCS) == 5
    assert await _user_count(ADMIN_DOC) == 1
    # Técnicos en estado pending (verificación admin, RF-AUTH-008) y libres.
    assert await _technician_count() == 5


async def test_seed_pilot_second_run_is_idempotent():
    summary = await seed_pilot()

    assert summary.clients_created == 0
    assert summary.technicians_created == 0
    assert summary.admin_created == 0
    assert summary.clients_existing == 5
    assert summary.technicians_existing == 5
    assert summary.admin_existing == 1
    # Sin duplicados en la DB.
    assert await _user_count(*CLIENT_DOCS) == 5
    assert await _user_count(*TECHNICIAN_DOCS) == 5
    assert await _user_count(ADMIN_DOC) == 1


async def test_teardown_pilot_removes_only_seed_docs():
    await teardown_pilot()

    assert await _user_count(*SEED_DOCS) == 0
    assert await _technician_count() == 0

    # Deja el seed canónico en pie para el resto de la suite.
    await seed_pilot()