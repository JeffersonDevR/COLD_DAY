from fastapi import FastAPI
from app.api.catalog import router as catalog_router
from app.api.services import router as services_router
from app.api.technicians import router as technicians_router
from app.api.auth import router as auth_router
from app.api.admin import router as admin_router
# Import de modelos para registrar el metadata (herramientas/migraciones); el
# esquema lo gobierna Alembic desde S6 (RF-PILOT-001) — create_all se eliminó.
from app.models import service as _service_models  # noqa: F401
from app.models.user import AuthToken, User  # noqa: F401

app = FastAPI(
    title="Cold Day API",
    description="MVP Backend para gestión de climatización y radar de técnicos",
    version="1.0.0",
)

app.include_router(catalog_router)
app.include_router(services_router)
app.include_router(technicians_router)
app.include_router(auth_router)
app.include_router(admin_router)


@app.get("/")
def read_root():
    return {
        "message": "Bienvenido al Backend de Cold Day ❄️",
        "docs": "/docs",
    }

