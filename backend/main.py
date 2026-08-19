from fastapi import FastAPI
from app.core.database import Base, engine
from app.api.catalog import router as catalog_router
from app.api.services import router as services_router
from app.api.technicians import router as technicians_router
from app.api.auth import router as auth_router
# Import de modelos para que create_all conozca todas las tablas (migraciones Alembic diferidas a S6).
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


@app.on_event("startup")
async def startup():
    
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


@app.get("/")
def read_root():
    return {
        "message": "Bienvenido al Backend de Cold Day ❄️",
        "docs": "/docs",
    }

