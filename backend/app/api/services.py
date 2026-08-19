from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.api.deps import get_current_user, require_roles
from app.core.database import get_db
from app.models.service import Equipment, ServiceRequest, Technician, TechnicianBid
from app.models.user import User
from app.schemas.service import ServiceRequestCreate, TechnicianBidCreate

router = APIRouter(prefix="/api/services", tags=["Services & Technician Bidding"])

EMPTY_AREA_MESSAGE = "No se encontraron técnicos en tu área"


@router.get("/technicians-nearby/")
async def find_technicians_nearby(
    latitude: float,
    longitude: float,
    radius_km: float = 5.0,
    specialty: str | None = None,
    min_rating: float | None = Query(default=None, ge=0, le=5),
    db: AsyncSession = Depends(get_db),
):
    """
    Radar de técnicos (RF-MATCH-001/002): solo técnicos `verified` y `free`
    dentro del radio; orden proximidad -> rating; filtros opcionales de
    especialidad y calificación mínima. Salida: perfil mínimo (RF-MATCH-003).
    """
    point = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)
    distance = func.ST_Distance(Technician.location, point)

    query = (
        select(Technician, distance.label("distance_deg"))
        .where(func.ST_DWithin(Technician.location, point, radius_km / 111.0))
        .where(Technician.verification_status == "verified")
        .where(Technician.availability == "free")
    )
    if specialty:
        query = query.where(Technician.specialty.ilike(f"%{specialty}%"))
    if min_rating is not None:
        query = query.where(Technician.rating >= min_rating)
    query = query.order_by(distance, Technician.rating.desc())

    result = await db.execute(query)
    technicians = []

    for tech, distance_deg in result.all():
        # 1 grado aprox = 111 km (promedio), suficiente para el MVP
        distance_km = round(float(distance_deg) * 111.0, 2)
        technicians.append(
            {
                "id": tech.id,
                "name": tech.name,
                "rating": tech.rating,
                "specialty": tech.specialty,
                "distance_km": distance_km,
            }
        )

    payload = {"count": len(technicians), "radius_km": radius_km, "technicians": technicians}
    if not technicians:
        payload["message"] = EMPTY_AREA_MESSAGE  # RF-MATCH-007
    return payload


@router.post("/", status_code=201)
async def create_service_request(
    payload: ServiceRequestCreate,
    user: User = Depends(get_current_user),  # RF-SR-001: dueño del token
    db: AsyncSession = Depends(get_db),
):
    # Validar que el equipo exista (RF-SR-011): el raise real -> 404, no 500.
    eq = await db.get(Equipment, payload.equipment_id)
    if eq is None:
        raise HTTPException(status_code=404, detail="Equipment not found")

    # Crear geometría PostGIS WKT POINT(longitude latitude)
    point_wkt = f"POINT({payload.longitude} {payload.latitude})"

    service_request = ServiceRequest(
        user_id=user.id,
        equipment_id=payload.equipment_id,
        service_type=payload.service_type,
        description=payload.description,
        location=point_wkt,
        budget_offered=payload.budget_offered,
        status="requested",
    )

    db.add(service_request)
    await db.commit()
    await db.refresh(service_request)

    return {
        "message": "Solicitud creada con éxito en el radar",
        "request_id": service_request.id,
        "status": service_request.status,
    }


@router.post("/bids/", status_code=201)
async def create_technician_bid(
    payload: TechnicianBidCreate,
    user: User = Depends(require_roles("technician")),  # technician_id del token
    db: AsyncSession = Depends(get_db),
):
    # Costos >= 0 (RF-SR-002): negativos -> 422 con el campo señalado.
    cost_errors = []
    if payload.transport_cost < 0:
        cost_errors.append(
            {"field": "transport_cost", "error": "Debe ser mayor o igual a 0"}
        )
    if payload.diagnosis_cost < 0:
        cost_errors.append(
            {"field": "diagnosis_cost", "error": "Debe ser mayor o igual a 0"}
        )
    if cost_errors:
        raise HTTPException(status_code=422, detail=cost_errors)

    # El rol `technician` ya está validado; el perfil de técnico existe siempre
    # que el registro haya pasado por /register/technician (RF-AUTH-002).
    technician = (
        await db.execute(select(Technician).where(Technician.user_id == user.id))
    ).scalar_one_or_none()
    if technician is None:
        raise HTTPException(status_code=403, detail="Perfil de técnico no encontrado")

    req = await db.get(ServiceRequest, payload.service_request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Service request not found")

    bid = TechnicianBid(
        service_request_id=payload.service_request_id,
        technician_id=technician.id,
        price_offered=payload.price_offered,
        estimated_time_minutes=payload.estimated_time_minutes,
        transport_cost=payload.transport_cost,
        diagnosis_cost=payload.diagnosis_cost,
        status="pending",
    )

    db.add(bid)
    if req.status == "requested":
        req.status = "bidding"  # primer bid abre el mercado (máquina PINNED)
    await db.commit()
    await db.refresh(bid)

    return {
        "message": "Contraoferta enviada al cliente",
        "bid_id": bid.id,
        "price_offered": bid.price_offered,
        "status": bid.status,
    }