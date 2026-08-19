"""Task 6.4 — RED/GREEN: URL de DB por entorno (RF-PILOT-002).

La URL de la base sale de `COLDDAY_DATABASE_URL`; sin la variable cae al
fallback localhost. El engine importado usa la misma fuente (chequeo en
tiempo de import, no de conexión — los tests corren sin tocar la DB).
"""

import pytest

from app.core.config import DEFAULT_DATABASE_URL, get_database_url
from app.core.database import engine


def test_database_url_falls_back_to_localhost_without_env(monkeypatch):
    monkeypatch.delenv("COLDDAY_DATABASE_URL", raising=False)
    assert get_database_url() == DEFAULT_DATABASE_URL


def test_database_url_reads_env_override(monkeypatch):
    custom = "postgresql+asyncpg://user:pass@db.internal:5433/coldday_prod"
    monkeypatch.setenv("COLDDAY_DATABASE_URL", custom)
    assert get_database_url() == custom


def test_engine_url_matches_config_source():
    # El engine de la app se construye con la misma fuente que expone config
    # (RF-PILOT-002): driver asyncpg sobre Postgres.
    assert str(engine.url).startswith("postgresql+asyncpg://")
    assert engine.url.get_backend_name() == "postgresql"
    assert engine.url.get_driver_name() == "asyncpg"