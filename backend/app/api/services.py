from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.core.database import get_db
from app.models.service import Equipment, ServiceRequest, Technician, TechnicianBid
from app.schemas.service import ServiceRequestCreate, TechnicianBidCreate

router = APIRouter(prefix="/api/services", tags=["Services & Technician Bidding"])


@router.get("/technicians-nearby/")
async def find_technicians_nearby(
    latitude: float,
    longitude: float,
    radius_km: float = 5.0,
    db: AsyncSession = Depends(get_db),
):
    """
    Radar de técnicos: busca técnicos en un radio (km) alrededor de un punto.

    Usa PostGIS ST_DWithin + ST_Distance para filtrar y ordenar por cercanía.
    """
    point = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)

    query = (
        select(
            Technician,
            func.ST_Distance(Technician.location, point).label("distance_deg"),
        )
        .where(func.ST_DWithin(Technician.location, point, radius_km / 111.0))
        .order_by("distance_deg")
    )

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

    return {"count": len(technicians), "radius_km": radius_km, "technicians": technicians}


@router.post("/", status_code=201)
async def create_service_request(
    payload: ServiceRequestCreate, db: AsyncSession = Depends(get_db)
):
    # Validar que el equipo exista
    eq = await db.get(Equipment, payload.equipment_id)
    not eq and HTTPException(status_404, detail="Equipment not found")

    # Crear geometría PostGIS WKT POINT(longitude latitude)
    point_wkt = f"POINT({payload.longitude} {payload.latitude})"

    service_request = ServiceRequest(
        user_id=payload.user_id,
        equipment_id=payload.equipment_id,
        service_type=payload.service_type,
        description=payload.description,
        location=point_wkt,
        budget_offered=payload.budget_offered,
        status="pending",
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
    payload: TechnicianBidCreate, db: AsyncSession = Depends(get_db)
):
    # El técnico envía su contraoferta
    req = await db.get(ServiceRequest, payload.service_request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Service request not found")

    bid = TechnicianBid(
        service_request_id=payload.service_request_id,
        technician_id=payload.technician_id,
        price_offered=payload.price_offered,
        estimated_time_minutes=payload.estimated_time_minutes,
        status="pending",
    )

    db.add(bid)
    req.status = "bidding"  # Actualizar estado a en puja
    await db.commit()
    await db.refresh(bid)

    return {
        "message": "Contraoferta enviada al cliente",
        "bid_id": bid.id,
        "price_offered": bid.price_offered,
    }
