from fastapi import FastAPI
from app.core.database import Base, engine
from app.api.catalog import router as catalog_router
from app.api.services import router as services_router

app = FastAPI(
    title="Cold Day API",
    description="MVP Backend para gestión de climatización y radar de técnicos",
    version="1.0.0",
)

app.include_router(catalog_router)
app.include_router(services_router)


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

