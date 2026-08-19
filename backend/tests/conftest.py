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
        # S3 pacto-vertical (design §Delta modelos): columnas nuevas sobre tablas
        # existentes — la migración real es S6 (RF-PILOT-001).
        await conn.execute(
            text(
                "ALTER TABLE service_requests "
                "ADD COLUMN IF NOT EXISTS assigned_technician_id "
                "integer REFERENCES technicians(id), "
                "ADD COLUMN IF NOT EXISTS diagnosis_observations text, "
                "ADD COLUMN IF NOT EXISTS created_at "
                "timestamptz NOT NULL DEFAULT now()"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE technician_bids "
                "ADD COLUMN IF NOT EXISTS created_at "
                "timestamptz NOT NULL DEFAULT now()"
            )
        )
        # FK real technician_bids.technician_id (0 huérfanos verificado en la DB
        # dev). service_requests.user_id NO puede constraint aún: hay filas
        # huérfanas históricas (riesgo documentado PR3) -> la FK real llega con
        # Alembic (S6). `ADD CONSTRAINT IF NOT EXISTS` no existe en Postgres:
        # el DO block la hace idempotente.
        await conn.execute(
            text(
                "DO $$ BEGIN "
                "IF NOT EXISTS ("
                "  SELECT 1 FROM pg_constraint WHERE conname = 'fk_technician_bids_technician'"
                ") THEN "
                "  ALTER TABLE technician_bids ADD CONSTRAINT "
                "fk_technician_bids_technician "
                "FOREIGN KEY (technician_id) REFERENCES technicians(id); "
                "END IF; "
                "END $$;"
            )
        )
        # S4 ratings (design §Delta modelos): `reviews` es tabla NUEVA -> create_all
        # la crea con su constraint único. El bridge garantiza RF-RAT-004 si la
        # tabla ya existía de una corrida previa sin el constraint (riesgo
        # documentado PR4: create_all no altera tablas existentes).
        await conn.execute(
            text(
                "DO $$ BEGIN "
                "IF to_regclass('public.reviews') IS NOT NULL "
                "AND NOT EXISTS ("
                "  SELECT 1 FROM pg_index WHERE indexrelid = "
                "  (SELECT indexrelid FROM pg_index i "
                "   JOIN pg_class c ON c.oid = i.indrelid "
                "   JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(i.indkey) "
                "   WHERE c.relname = 'reviews' AND a.attname = 'service_request_id' "
                "   AND i.indisunique)"
                ") THEN "
                "  ALTER TABLE reviews ADD CONSTRAINT uq_reviews_service_request "
                "  UNIQUE (service_request_id); "
                "END IF; "
                "END $$;"
            )
        )


@pytest.fixture(scope="session", autouse=True)
async def _cleanup_test_data(_ensure_schema):
    """Remove every row created by this test session (auth + technicians + users)."""
    yield
    async with AsyncSessionLocal() as session:
        # S4 ratings: reviews referencia requests/technicians/users -> borrar
        # PRIMERO (FK order: reviews -> agreements -> bids -> requests).
        has_reviews = (
            await session.execute(
                text("SELECT to_regclass('public.reviews')")
            )
        ).scalar()
        if has_reviews is not None:
            await session.execute(
                text(
                    "DELETE FROM reviews WHERE service_request_id IN "
                    f"(SELECT id FROM service_requests WHERE user_id IN "
                    f"(SELECT id FROM users WHERE document LIKE '{_TEST_DOC_PREFIX}%'))"
                )
            )
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
                "DELETE FROM service_agreements WHERE service_request_id IN "
                f"(SELECT id FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE document LIKE '{_TEST_DOC_PREFIX}%'))"
            )
        )
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