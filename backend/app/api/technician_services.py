from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload

from app.api.deps import require_roles
from app.core.database import get_db
from app.models.service import EquipmentCategory, Technician, TechnicianService
from app.models.user import User
from app.schemas.service import TechnicianServiceCreate, TechnicianServiceOut

router = APIRouter(prefix="/api/technicians/me/services", tags=["Technician Services"])

async def _current_technician(db: AsyncSession, user: User) -> Technician:
    technician = (
        await db.execute(select(Technician).where(Technician.user_id == user.id))
    ).scalar_one_or_none()
    if technician is None:
        raise HTTPException(status_code=403, detail="Perfil de técnico no encontrado")
    return technician

@router.get("", response_model=list[TechnicianServiceOut])
async def list_my_services(
    user: User = Depends(require_roles("technician")),
    db: AsyncSession = Depends(get_db),
):
    tech = await _current_technician(db, user)
    result = await db.execute(
        select(TechnicianService)
        .options(selectinload(TechnicianService.category))
        .where(TechnicianService.technician_id == tech.id)
    )
    services = result.scalars().all()
    return [
        TechnicianServiceOut(
            id=s.id,
            category_id=s.category_id,
            category_name=s.category.name if s.category else None,
            service_types=s.service_types,
            sector=s.sector,
            active=s.active,
        )
        for s in services
    ]

@router.post("", response_model=TechnicianServiceOut, status_code=201)
async def add_service(
    payload: TechnicianServiceCreate,
    user: User = Depends(require_roles("technician")),
    db: AsyncSession = Depends(get_db),
):
    tech = await _current_technician(db, user)
    
    # Check if category exists
    cat = await db.get(EquipmentCategory, payload.category_id)
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")
        
    # Check for existing service
    existing = await db.execute(
        select(TechnicianService).where(
            TechnicianService.technician_id == tech.id,
            TechnicianService.category_id == payload.category_id
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Service for this category already exists")
        
    new_service = TechnicianService(
        technician_id=tech.id,
        category_id=payload.category_id,
        service_types=payload.service_types,
        sector=payload.sector,
        active=True
    )
    db.add(new_service)
    await db.commit()
    await db.refresh(new_service)
    
    return TechnicianServiceOut(
        id=new_service.id,
        category_id=new_service.category_id,
        category_name=cat.name,
        service_types=new_service.service_types,
        sector=new_service.sector,
        active=new_service.active
    )

@router.delete("/{service_id}", status_code=204)
async def remove_service(
    service_id: int,
    user: User = Depends(require_roles("technician")),
    db: AsyncSession = Depends(get_db),
):
    tech = await _current_technician(db, user)
    service = await db.get(TechnicianService, service_id)
    if not service or service.technician_id != tech.id:
        raise HTTPException(status_code=404, detail="Service not found")
        
    await db.delete(service)
    await db.commit()
