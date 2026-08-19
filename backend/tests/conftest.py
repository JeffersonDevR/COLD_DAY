"""Shared fixtures for backend tests.

Estrategia de testing (design §Estrategia): separación smoke/integración
(RF-PILOT-005). Los tests marcados `integration` corren contra la DB PostGIS
local (`coldday`) y se skipean si no hay PostGIS; el resto (smoke/unit) corre
sin DB. El esquema se bootstrapa con `create_all` + `ALTER` idempotentes
SOLO cuando hay tests de integración Y la DB está disponible — el bridge de
ALTERs queda como helper de tests (la producción usa Alembic desde S6,
RF-PILOT-001).
"""

import psycopg2
import pytest
from sqlalchemy import text

from app.core.config import get_database_url
from app.core.database import AsyncSessionLocal, Base, engine

# Import models so Base.metadata knows every table before create_all.
from app.models import service as _service_models  # noqa: F401
from app.models.user import AuthToken, User  # noqa: F401

# Documents of test users always start with this prefix; the cleanup fixture
# uses it to remove only the rows this test session created. El admin del
# seed piloto (1000000001, seed_admin.py / seed_pilot.py) queda EXCLUIDO: el
# cleanup de tests no debe borrar datos sembrados para el piloto real.
_TEST_DOC_PREFIX = "100"
_PILOT_ADMIN_DOC = "1000000001"

# The session-scoped fixtures below connect to PostgreSQL. En smoke runs
# (sin tests `integration`) ese bootstrap no debe ocurrir: ver
# `pytest_collection_modifyitems` (solo smoke -> _SMOKE_ONLY True).
_POSTGIS_AVAILABLE: bool | None = None
_SMOKE_ONLY = False


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "integration: tests that require a local PostGIS database"
    )


def _postgis_available() -> bool:
    """Cachea un chequeo real: conexión + extensión PostGIS (3s timeout)."""
    global _POSTGIS_AVAILABLE
    if _POSTGIS_AVAILABLE is None:
        # Misma fuente de URL que la app (RF-PILOT-002), driver síncrono.
        sync_url = get_database_url().replace("+asyncpg", "")
        try:
            conn = psycopg2.connect(sync_url, connect_timeout=3)
            try:
                with conn.cursor() as cur:
                    cur.execute("SELECT postgis_version()")
                    _POSTGIS_AVAILABLE = cur.fetchone() is not None
            finally:
                conn.close()
        except Exception:  # noqa: BLE001 — cualquier fallo = no hay PostGIS
            _POSTGIS_AVAILABLE = False
    return _POSTGIS_AVAILABLE


def pytest_collection_modifyitems(config, items):
    """Divide la suite: smoke (sin DB) vs integración (marker + skip).

    - Si NO hay tests `integration` en la colección -> solo smoke: nadie toca
      la DB (el fixture `_ensure_schema` se vuelve no-op).
    - Si los hay pero PostGIS no está disponible -> se skipean con motivo.
    """
    global _SMOKE_ONLY
    has_integration = any("integration" in item.keywords for item in items)
    if not has_integration:
        _SMOKE_ONLY = True
        return
    if not _postgis_available():
        skip = pytest.mark.skip(
            reason="PostGIS no disponible: se omiten los tests de integración"
        )
        for item in items:
            if "integration" in item.keywords:
                item.add_marker(skip)


def _test_user_docs_filter() -> str:
    """WHERE de documentos de prueba, preservando el admin del seed piloto."""
    return (
        f"document LIKE '{_TEST_DOC_PREFIX}%' AND document <> '{_PILOT_ADMIN_DOC}'"
    )


@pytest.fixture(scope="session", autouse=True)
async def _ensure_schema():
    """Make the dev DB schema match the ORM models (create_all + idempotent ALTERs).

    NO-op en corridas smoke (sin tests `integration`) o sin PostGIS: los tests
    unitarios no deben tocar la DB (RF-PILOT-005).
    """
    if _SMOKE_ONLY or not _postgis_available():
        return
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
    """Remove every row created by this test session (auth + technicians + users).

    Solo toca datos de pruebas (documentos `100...` salvo el admin del seed
    piloto 1000000001) y técnicos vinculados a usuarios de prueba — nunca el
    seed piloto (2000000001.., 3000000001..) ni los técnicos legacy.
    """
    if _SMOKE_ONLY or not _postgis_available():
        yield
        return
    yield
    docs_filter = _test_user_docs_filter()
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
                    f"(SELECT id FROM users WHERE {docs_filter}))"
                )
            )
        await session.execute(
            text(
                "DELETE FROM auth_tokens WHERE user_id IN "
                f"(SELECT id FROM users WHERE {docs_filter})"
            )
        )
        # S2 contract-fix tests create requests and bids (user_id sin FK real
        # hasta S6); borralos antes de los users dueños.
        await session.execute(
            text(
                "DELETE FROM service_agreements WHERE service_request_id IN "
                f"(SELECT id FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE {docs_filter}))"
            )
        )
        await session.execute(
            text(
                "DELETE FROM technician_bids WHERE service_request_id IN "
                f"(SELECT id FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE {docs_filter}))"
            )
        )
        await session.execute(
            text(
                f"DELETE FROM service_requests WHERE user_id IN "
                f"(SELECT id FROM users WHERE {docs_filter})"
            )
        )
        # Solo técnicos creados por pruebas (user_id ligado a un user de
        # prueba); el seed piloto (3000000001..) y los legacy (user_id NULL)
        # se conservan.
        await session.execute(
            text(
                f"DELETE FROM technicians WHERE user_id IN "
                f"(SELECT id FROM users WHERE {docs_filter})"
            )
        )
        await session.execute(text(f"DELETE FROM users WHERE {docs_filter}"))
        await session.commit()