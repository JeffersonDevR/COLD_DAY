from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func

from app.api.deps import require_roles, get_current_user
from app.core.database import get_db
from app.models.service import ServiceRequest, Technician, LocationUpdate
from app.models.user import User
from app.schemas.service import LocationUpdateCreate

router = APIRouter(prefix="/api/tracking", tags=["Tracking"])

async def _current_technician(db: AsyncSession, user: User) -> Technician:
    technician = (
        await db.execute(select(Technician).where(Technician.user_id == user.id))
    ).scalar_one_or_none()
    if technician is None:
        raise HTTPException(status_code=403, detail="Perfil de técnico no encontrado")
    return technician

@router.post("/{request_id}/location", status_code=201)
async def update_location(
    request_id: int,
    payload: LocationUpdateCreate,
    user: User = Depends(require_roles("technician")),
    db: AsyncSession = Depends(get_db),
):
    tech = await _current_technician(db, user)
    
    # Verify request and assignment
    req = await db.get(ServiceRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Service request not found")
        
    if req.assigned_technician_id != tech.id:
        raise HTTPException(status_code=403, detail="Not assigned to this request")
        
    point_wkt = f"POINT({payload.longitude} {payload.latitude})"
    update = LocationUpdate(
        service_request_id=request_id,
        technician_id=tech.id,
        location=point_wkt
    )
    
    # Also update the technician's current location
    tech.location = point_wkt
    
    db.add(update)
    await db.commit()
    
    return {"message": "Location updated successfully"}

@router.get("/{request_id}/location")
async def get_location(
    request_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    req = await db.get(ServiceRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Service request not found")
        
    # Check ownership or if it's the assigned technician
    is_assigned = False
    if user.role == "technician":
        tech = await db.execute(select(Technician).where(Technician.user_id == user.id))
        tech = tech.scalar_one_or_none()
        if tech and req.assigned_technician_id == tech.id:
            is_assigned = True
            
    if user.role != "admin" and req.user_id != user.id and not is_assigned:
        raise HTTPException(status_code=403, detail="Not authorized to track this request")
        
    # Get latest update
    result = await db.execute(
        select(
            func.ST_Y(LocationUpdate.location).label("latitude"),
            func.ST_X(LocationUpdate.location).label("longitude"),
            LocationUpdate.created_at
        )
        .where(LocationUpdate.service_request_id == request_id)
        .order_by(LocationUpdate.created_at.desc())
        .limit(1)
    )
    update = result.first()
    
    if not update:
        return {"latitude": None, "longitude": None, "updated_at": None}
        
    return {
        "latitude": float(update.latitude),
        "longitude": float(update.longitude),
        "updated_at": update.created_at.isoformat() if update.created_at else None
    }
