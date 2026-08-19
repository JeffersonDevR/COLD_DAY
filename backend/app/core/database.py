from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from app.core.config import get_database_url

# Configuración de base de datos asíncrona con PostgreSQL / PostGIS
# (RF-PILOT-002): la URL sale de COLDDAY_DATABASE_URL con fallback localhost.
DATABASE_URL = get_database_url()

engine = create_async_engine(DATABASE_URL, echo=True, future=True)
AsyncSessionLocal = sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

Base = declarative_base()


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
