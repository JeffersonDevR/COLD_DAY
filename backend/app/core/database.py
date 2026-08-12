from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# Configuración de base de datos asíncrona con PostgreSQL / PostGIS
# Ejemplo: postgresql+asyncpg://user:password@localhost:5432/coldday
DATABASE_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/coldday"

engine = create_async_engine(DATABASE_URL, echo=True, future=True)
AsyncSessionLocal = sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

Base = declarative_base()


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
