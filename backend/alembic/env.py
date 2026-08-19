"""Alembic environment (S6 mvp-polish, RF-PILOT-001): async + asyncpg.

La URL sale de `COLDDAY_DATABASE_URL` (app.core.config) — el valor de
alembic.ini solo es placeholder. Import de modelos para que
`target_metadata` conozca TODAS las tablas (users, service_agreements,
reviews, Geometry PostGIS, etc.).
"""

import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

import geoalchemy2  # noqa: F401  (registra Geometry en autogenerate)

from app.core.config import get_database_url
from app.core.database import Base
from app.models import service as _service_models  # noqa: F401
from app.models.user import AuthToken, User  # noqa: F401

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# URL real: env var (RF-PILOT-002) con override puntual `-x url=...` para
# pruebas sobre DBs temporales (p.ej. validar upgrade/downgrade).
config.set_main_option(
    "sqlalchemy.url",
    context.get_x_argument(as_dictionary=True).get("url") or get_database_url(),
)

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode (emite SQL sin conectar)."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)

    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    """Async engine (asyncpg) + run_sync hacia do_run_migrations."""
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()