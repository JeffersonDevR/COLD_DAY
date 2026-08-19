"""Configuración de la aplicación (S6 hardening, RF-PILOT-002).

La URL de la base de datos sale de la variable de entorno
`COLDDAY_DATABASE_URL` con fallback a la DB local de desarrollo — el valor
hardcodeado anterior en `core/database.py` se elimina.
"""

import os

# Fallback de desarrollo (mismo valor que usaba database.py hasta S6).
DEFAULT_DATABASE_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/coldday"


def get_database_url() -> str:
    """URL asyncpg de la DB: env `COLDDAY_DATABASE_URL` o fallback localhost."""
    return os.environ.get("COLDDAY_DATABASE_URL", DEFAULT_DATABASE_URL)