"""Shared fixtures for backend tests.

Integration tests run against the local PostGIS database (`coldday`).
Schema is bootstrapped with `create_all` plus idempotent `ALTER TABLE`
statements because Alembic migrations are deferred to slice S6 (hardening).
"""

import pytest
from sqlalchemy import text

from app.core.database import AsyncSessionLocal, Base, engine

# Import models so Base.metadata knows every table before create_all.
from app.models import service as _service_models  # noqa: F401
from app.models.user import AuthToken, User  # noqa: F401

# Documents of test users always start with this prefix; the cleanup fixture
# uses it to remove only the rows this test session created.
_TEST_DOC_PREFIX = "100"


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "integration: tests that require a local PostGIS database"
    )


@pytest.fixture(scope="session", autouse=True)
async def _ensure_schema():
    """Make the dev DB schema match the ORM models (create_all + idempotent ALTERs)."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Technician delta from slice S1; ADD COLUMN IF NOT EXISTS keeps this
        # idempotent and preserves existing rows until S6 replaces create_all.
        await conn.execute(
            text(
                "ALTER TABLE technicians "
                "ADD COLUMN IF NOT EXISTS user_id integer REFERENCES users(id), "
                "ADD COLUMN IF NOT EXISTS verification_status "
                "varchar(20) NOT NULL DEFAULT 'pending', "
                "ADD COLUMN IF NOT EXISTS rejection_reason text, "
                "ADD COLUMN IF NOT EXISTS availability varchar(10) NOT NULL DEFAULT 'free'"
            )
        )
        # TechnicianBid cost columns (S2 contract fix, RF-SR-002): the baseline
        # DB predates transport_cost/diagnosis_cost; create_all won't add
        # columns to an existing table.
        await conn.execute(
            text(
                "ALTER TABLE technician_bids "
                "ADD COLUMN IF NOT EXISTS transport_cost "
                "double precision NOT NULL DEFAULT 0.0, "
                "ADD COLUMN IF NOT EXISTS diagnosis_cost "
                "double precision NOT NULL DEFAULT 0.0"
            )
        )


@pytest.fixture(scope="session", autouse=True)
async def _cleanup_test_data(_ensure_schema):
    """Remove every row created by this test session (auth + technicians + users)."""
    yield
    async with AsyncSessionLocal() as session:
        await session.execute(
            text(
                "DELETE FROM auth_tokens WHERE user_id IN "
                f"(SELECT id FROM users WHERE document LIKE '{_TEST_DOC_PREFIX}%')"
            )
        )
        # S2 contract-fix tests create requests and bids (user_id sin FK real
        # hasta S6); borralos antes de los users dueños.
        await session.execute(
            text(
                "DELETE FROM technician_bids WHERE service_request_id IN "
                f"(SELECT id FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE document LIKE '{_TEST_DOC_PREFIX}%'))"
            )
        )
        await session.execute(
            text(
                f"DELETE FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE document LIKE '{_TEST_DOC_PREFIX}%')"
            )
        )
        await session.execute(
            text("DELETE FROM technicians WHERE user_id IS NOT NULL")
        )
        await session.execute(
            text(f"DELETE FROM users WHERE document LIKE '{_TEST_DOC_PREFIX}%'")
        )
        await session.commit()