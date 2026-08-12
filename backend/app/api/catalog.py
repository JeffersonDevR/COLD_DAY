from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.core.database import get_db
from app.models.service import Equipment, EquipmentCategory

router = APIRouter(prefix="/api/catalog", tags=["Catalog"])


@router.get("/")
async def get_catalog(db: AsyncSession = Depends(get_db)):
    """
    Catálogo data-driven (flujo Luis Santander):
    categoría (Neveras, Cuartos fríos, Aire acondicionado, Lavadoras,
    Electricidad, Electrónica, Instalación de cámaras)
      -> tecnologías aplicables (conventional/inverter) si la categoría las tiene
      -> equipos por sector (residential/industrial)

    La UI lo consume directo, así el mapeo fino se edita en la DB
    sin tocar código.
    """
    categories = await db.execute(
        select(EquipmentCategory)
        .options(selectinload(EquipmentCategory.equipments))
        .order_by(EquipmentCategory.id)
    )
    categories = categories.scalars().all()

    result = []
    for cat in categories:
        equipments_by_sector = {"residential": [], "industrial": []}
        for eq in cat.equipments:
            equipments_by_sector[eq.sector].append(
                {
                    "id": eq.id,
                    "name": eq.name,
                    "description": eq.description,
                }
            )

        result.append(
            {
                "id": cat.id,
                "name": cat.name,
                "icon": cat.icon,
                "technologies": cat.technologies or [],
                "residential": equipments_by_sector["residential"],
                "industrial": equipments_by_sector["industrial"],
            }
        )

    return {"categories": result}
