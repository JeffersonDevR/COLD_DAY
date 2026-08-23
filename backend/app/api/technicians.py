"""Radar del técnico (RF-MATCH-004/005).

Serializa solicitudes cercanas como DTO (id, equipo, descripción, lat/lng,
status) en lugar de ORM crudo (repara el 500 de serialización), lista solo
solicitudes `requested`/`bidding` dentro del radio y muestra el estado del bid
del técnico en solicitudes que ya ofertó (evita duplicar ofertas).
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import require_roles
from app.core.database import get_db
from app.models.service import ServiceRequest, Technician
from app.models.user import User

router = APIRouter(prefix="/api/technicians", tags=["Technicians"])

ACTIVE_RADAR_STATUSES = ("requested", "bidding")


@router.get("/requests/nearby/")
async def find_requests_nearby(
    radius_km: float = Query(default=10.0, gt=0, le=100),
    user: User = Depends(require_roles("technician")),
    db: AsyncSession = Depends(get_db),
):
    # Identidad del técnico desde el token (no confiar en query params).
    technician = (
        await db.execute(select(Technician).where(Technician.user_id == user.id))
    ).scalar_one_or_none()
    if technician is None:
        raise HTTPException(status_code=403, detail="Perfil de técnico no encontrado")
    if technician.verification_status != "verified":
        raise HTTPException(
            status_code=403,
            detail="El técnico debe estar verificado para usar el radar",
        )

    point = technician.location

    result = await db.execute(
        select(
            ServiceRequest,
            func.ST_Y(ServiceRequest.location).label("latitude"),
            func.ST_X(ServiceRequest.location).label("longitude"),
        )
        .options(
            selectinload(ServiceRequest.equipment),
            selectinload(ServiceRequest.bids),
        )
        .where(ServiceRequest.status.in_(ACTIVE_RADAR_STATUSES))
        .where(func.ST_DWithin(ServiceRequest.location, point, radius_km / 111.0))
        .where(ServiceRequest.location.is_not(None))
        .where(func.ST_IsValid(ServiceRequest.location))
        .where(func.ST_Y(ServiceRequest.location).between(-90, 90))
        .where(func.ST_X(ServiceRequest.location).between(-180, 180))
        .order_by(ServiceRequest.id.desc())
    )

    requests = []
    for req, latitude, longitude in result.all():
        if (
            latitude is None
            or longitude is None
            or not -90 <= float(latitude) <= 90
            or not -180 <= float(longitude) <= 180
        ):
            continue
        my_bid = next(
            (bid for bid in req.bids if bid.technician_id == technician.id), None
        )
        requests.append(
            {
                "id": req.id,
                "equipment": req.equipment.name if req.equipment else None,
                "description": req.description,
                "latitude": float(latitude),
                "longitude": float(longitude),
                "status": req.status,
                # RF-MATCH-005: solicitud ya ofertada muestra el estado del bid.
                "my_bid_status": my_bid.status if my_bid else None,
            }
        )

    return {"requests": requests}
