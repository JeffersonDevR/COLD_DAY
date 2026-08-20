from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, String
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload
from app.api.deps import get_current_user, require_roles
from app.core.database import get_db
from app.models.service import (
    Equipment,
    EquipmentCategory,
    ServiceAgreement,
    ServiceRequest,
    Technician,
    TechnicianBid,
    TechnicianService,
)
from app.models.user import User
from app.schemas.service import (
    AgreementCreate,
    DiagnosisCreate,
    ReviewCreate,
    ServiceRequestCreate,
    TechnicianBidCreate,
)
from app.services import lifecycle, ratings

router = APIRouter(prefix="/api/services", tags=["Services & Technician Bidding"])

EMPTY_AREA_MESSAGE = "No se encontraron técnicos en tu área"


async def _current_technician(db: AsyncSession, user: User) -> Technician:
    """Perfil de técnico del usuario autenticado (403 si no existe)."""
    technician = (
        await db.execute(select(Technician).where(Technician.user_id == user.id))
    ).scalar_one_or_none()
    if technician is None:
        raise HTTPException(status_code=403, detail="Perfil de técnico no encontrado")
    return technician


@router.get("/technicians-nearby/")
async def find_technicians_nearby(
    latitude: float,
    longitude: float,
    radius_km: float = 5.0,
    specialty: str | None = None,
    service_type: str | None = None,
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
        .options(
            selectinload(Technician.services).selectinload(TechnicianService.category)
        )
        .where(func.ST_DWithin(Technician.location, point, radius_km / 111.0))
        .where(Technician.verification_status == "verified")
        .where(Technician.availability == "free")
    )
    if specialty or service_type:
        query = query.join(Technician.services).join(EquipmentCategory)
        if specialty:
            query = query.where(EquipmentCategory.name.ilike(f"%{specialty}%"))
        if service_type:
            query = query.where(func.cast(TechnicianService.service_types, String).ilike(f"%{service_type}%"))

    if min_rating is not None:
        query = query.where(Technician.rating >= min_rating)
    query = query.order_by(distance, Technician.rating.desc())

    result = await db.execute(query)
    technicians = []

    for tech, distance_deg in result.unique().all():
        distance_km = round(float(distance_deg) * 111.0, 2)
        offered_services = []
        for svc in tech.services:
            if svc.active:
                offered_services.append({
                    "category": svc.category.name if svc.category else None,
                    "service_types": svc.service_types,
                    "sector": svc.sector
                })
        technicians.append(
            {
                "id": tech.id,
                "name": tech.name,
                "rating": tech.rating,
                "specialty": tech.specialty,
                "distance_km": distance_km,
                "services": offered_services
            }
        )

    payload = {"count": len(technicians), "radius_km": radius_km, "technicians": technicians}
    if not technicians:
        payload["message"] = EMPTY_AREA_MESSAGE  # RF-MATCH-007
    return payload


@router.get("/my")
async def my_service_requests(
    user: User = Depends(require_roles("client")),
    db: AsyncSession = Depends(get_db),
):
    """Historial del cliente dueño, fecha desc (RF-SR-010).

    Solo las solicitudes del usuario autenticado; las ajenas nunca aparecen
    (RF-SR-012).
    """
    result = await db.execute(
        select(ServiceRequest)
        .options(
            selectinload(ServiceRequest.equipment),
            selectinload(ServiceRequest.assigned_technician),
        )
        .where(ServiceRequest.user_id == user.id)
        .order_by(ServiceRequest.created_at.desc())
    )
    return {
        "requests": [_request_summary(req) for req in result.scalars().all()]
    }


@router.post("/", status_code=201)
async def create_service_request(
    payload: ServiceRequestCreate,
    user: User = Depends(get_current_user),  # RF-SR-001: dueño del token
    db: AsyncSession = Depends(get_db),
):
    # Validar que el equipo exista (RF-SR-011): el raise real -> 404, no 500.
    if payload.equipment_id is not None:
        eq = await db.get(Equipment, payload.equipment_id)
        if eq is None:
            raise HTTPException(status_code=404, detail="Equipment not found")

    # Crear geometría PostGIS WKT POINT(longitude latitude)
    point_wkt = f"POINT({payload.longitude} {payload.latitude})"

    service_request = ServiceRequest(
        user_id=user.id,
        equipment_id=payload.equipment_id,
        category_hint=payload.category_hint,
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

    technician = await _current_technician(db, user)
    # La máquina de estados valida verified+free, mercado abierto y duplicado
    # 409 (RF-TEC-005/006/007) dentro de su transacción atómica (3.4).
    bid = await lifecycle.create_bid(
        db,
        technician=technician,
        request_id=payload.service_request_id,
        price_offered=payload.price_offered,
        estimated_time_minutes=payload.estimated_time_minutes,
        transport_cost=payload.transport_cost,
        diagnosis_cost=payload.diagnosis_cost,
    )

    return {
        "message": "Contraoferta enviada al cliente",
        "bid_id": bid.id,
        "price_offered": bid.price_offered,
        "status": bid.status,
    }


@router.post("/{service_request_id}/bids/{bid_id}/accept")
async def accept_bid(
    service_request_id: int,
    bid_id: int,
    user: User = Depends(require_roles("client")),
    db: AsyncSession = Depends(get_db),
):
    """RF-SR-003: el cliente dueño acepta un bid desde `bidding` (atómico)."""
    request = await lifecycle.accept_bid(
        db, request_id=service_request_id, bid_id=bid_id, user_id=user.id
    )
    return {
        "message": "Oferta aceptada, el técnico realizará el diagnóstico",
        "request_id": request.id,
        "status": request.status,
        "technician_id": request.assigned_technician_id,
    }


@router.post("/{service_request_id}/diagnosis")
async def register_diagnosis(
    service_request_id: int,
    payload: DiagnosisCreate,
    user: User = Depends(require_roles("technician")),
    db: AsyncSession = Depends(get_db),
):
    """RF-SR-004: el técnico asignado registra las observaciones del diagnóstico."""
    technician = await _current_technician(db, user)
    request = await lifecycle.register_diagnosis(
        db,
        request_id=service_request_id,
        technician=technician,
        observations=payload.observations,
    )
    return {
        "message": "Diagnóstico registrado",
        "request_id": request.id,
        "status": request.status,
    }


@router.post("/{service_request_id}/agreements/", status_code=201)
async def create_agreement(
    service_request_id: int,
    payload: AgreementCreate,
    user: User = Depends(require_roles("technician")),
    db: AsyncSession = Depends(get_db),
):
    """RF-SR-005: el técnico asignado propone el pacto con desglose (atómico)."""
    technician = await _current_technician(db, user)
    pact = await lifecycle.create_agreement(
        db,
        request_id=service_request_id,
        technician=technician,
        labor_cost=payload.labor_cost,
        transport_cost=payload.transport_cost,
        diagnosis_cost=payload.diagnosis_cost,
        observations=payload.observations,
    )
    return {
        "message": "Pacto de servicio propuesto al cliente",
        "agreement_id": pact.id,
        "request_id": pact.service_request_id,
        "total": pact.total,
        "status": pact.status,
    }


@router.post("/{service_request_id}/agreements/{agreement_id}/accept")
async def accept_agreement(
    service_request_id: int,
    agreement_id: int,
    user: User = Depends(require_roles("client")),
    db: AsyncSession = Depends(get_db),
):
    """RF-SR-006: el cliente dueño acepta el pacto -> in_progress (atómico)."""
    request = await lifecycle.accept_pact(
        db, request_id=service_request_id, agreement_id=agreement_id, user_id=user.id
    )
    return {
        "message": "Pacto aceptado, el servicio está en proceso",
        "request_id": request.id,
        "status": request.status,
    }


@router.post("/{service_request_id}/agreements/{agreement_id}/reject")
async def reject_agreement(
    service_request_id: int,
    agreement_id: int,
    user: User = Depends(require_roles("client")),
    db: AsyncSession = Depends(get_db),
):
    """RF-SR-007: rechazo del pacto reabre el mercado (todos los bids a pending)."""
    request = await lifecycle.reject_pact(
        db, request_id=service_request_id, agreement_id=agreement_id, user_id=user.id
    )
    return {
        "message": "Pacto rechazado, las ofertas vuelven a estar disponibles",
        "request_id": request.id,
        "status": request.status,
    }


@router.post("/{service_request_id}/complete")
async def complete_service_request(
    service_request_id: int,
    user: User = Depends(require_roles("technician")),
    db: AsyncSession = Depends(get_db),
):
    """RF-SR-008: el técnico asignado finaliza el servicio desde `in_progress`."""
    technician = await _current_technician(db, user)
    request = await lifecycle.complete_request(
        db, request_id=service_request_id, technician=technician
    )
    return {
        "message": "Servicio completado",
        "request_id": request.id,
        "status": request.status,
    }


@router.post("/{service_request_id}/review/", status_code=201)
async def create_review(
    service_request_id: int,
    payload: ReviewCreate,
    user: User = Depends(require_roles("client")),  # RF-RAT-001: solo cliente dueño
    db: AsyncSession = Depends(get_db),
):
    """RF-RAT-001..006: evaluación post-servicio (3 dims + comentario <= 1000).

    Validaciones en el servicio (orden spec): ajeno -> 403, no completada -> 422,
    duplicado por request -> 409 (constraint único), y recálculo de
    Technician.rating como promedio 1 decimal (RF-RAT-005).
    """
    review, new_rating = await ratings.create_review(
        db,
        request_id=service_request_id,
        client=user,
        punctuality=payload.punctuality,
        quality=payload.quality,
        professionalism=payload.professionalism,
        comment=payload.comment,
    )
    return {
        "message": "Calificación registrada, ¡gracias!",
        "review_id": review.id,
        "global_score": review.global_score,
        "technician_rating": new_rating,
    }


@router.post("/{service_request_id}/cancel")
async def cancel_service_request(
    service_request_id: int,
    user: User = Depends(require_roles("client")),
    db: AsyncSession = Depends(get_db),
):
    """RF-SR-009: cancelación del dueño solo desde requested/bidding (atómico)."""
    request = await lifecycle.cancel_request(
        db, request_id=service_request_id, user_id=user.id
    )
    return {
        "message": "Solicitud cancelada",
        "request_id": request.id,
        "status": request.status,
    }


@router.get("/{service_request_id}")
async def get_service_request_detail(
    service_request_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Detalle con técnico y línea de tiempo (RF-SR-010/012).

    Visible solo para el dueño, el técnico asignado y admin; ajeno -> 404.
    """
    result = await db.execute(
        select(ServiceRequest)
        .options(
            selectinload(ServiceRequest.equipment),
            selectinload(ServiceRequest.bids).selectinload(TechnicianBid.technician),
            selectinload(ServiceRequest.agreements),
            selectinload(ServiceRequest.assigned_technician),
        )
        .where(ServiceRequest.id == service_request_id)
    )
    request = result.scalar_one_or_none()
    if request is None:
        raise HTTPException(status_code=404, detail="Service request not found")

    if not _can_view(request, user):
        raise HTTPException(status_code=404, detail="Service request not found")

    technician = request.assigned_technician
    return _request_detail(request, technician)


def _can_view(request: ServiceRequest, user: User) -> bool:
    """RF-SR-012: dueño, técnico asignado o admin."""
    if user.role == "admin" or request.user_id == user.id:
        return True
    if user.role == "technician" and request.assigned_technician is not None:
        # El técnico asignado se identifica por su perfil, no por user.id.
        return request.assigned_technician.user_id == user.id
    return False


def _request_summary(request: ServiceRequest) -> dict:
    """Ítem del historial del cliente (GET /api/services/my)."""
    technician = request.assigned_technician
    return {
        "id": request.id,
        "status": request.status,
        "service_type": request.service_type,
        "description": request.description,
        "equipment": request.equipment.name if request.equipment else None,
        "created_at": request.created_at.isoformat() if request.created_at else None,
        "budget_offered": request.budget_offered,
        "technician": (
            {
                "id": technician.id,
                "name": technician.name,
                "rating": technician.rating,
                "specialty": technician.specialty,
            }
            if technician
            else None
        ),
    }


def _request_detail(request: ServiceRequest, technician: Technician | None) -> dict:
    """Detalle completo con línea de tiempo (RF-SR-010)."""
    return {
        "id": request.id,
        "status": request.status,
        "service_type": request.service_type,
        "description": request.description,
        "equipment": (
            {
                "id": request.equipment.id,
                "name": request.equipment.name,
                "sector": request.equipment.sector,
            }
            if request.equipment
            else None
        ),
        "created_at": request.created_at.isoformat() if request.created_at else None,
        "budget_offered": request.budget_offered,
        "diagnosis_observations": request.diagnosis_observations,
        "technician": (
            {
                "id": technician.id,
                "name": technician.name,
                "rating": technician.rating,
                "specialty": technician.specialty,
            }
            if technician
            else None
        ),
        # Línea de tiempo: bids y pactos en orden cronológico (RF-SR-010).
        "timeline": {
            "bids": [
                {
                    "id": bid.id,
                    "technician_id": bid.technician_id,
                    "technician_name": bid.technician.name if bid.technician else None,
                    "price_offered": bid.price_offered,
                    "transport_cost": bid.transport_cost,
                    "diagnosis_cost": bid.diagnosis_cost,
                    "estimated_time_minutes": bid.estimated_time_minutes,
                    "status": bid.status,
                    "created_at": (
                        bid.created_at.isoformat() if bid.created_at else None
                    ),
                }
                for bid in request.bids
            ],
            "agreements": [
                {
                    "id": pact.id,
                    "technician_id": pact.technician_id,
                    "labor_cost": pact.labor_cost,
                    "transport_cost": pact.transport_cost,
                    "diagnosis_cost": pact.diagnosis_cost,
                    "total": pact.total,
                    "observations": pact.observations,
                    "status": pact.status,
                    "created_at": (
                        pact.created_at.isoformat() if pact.created_at else None
                    ),
                    "decided_at": (
                        pact.decided_at.isoformat() if pact.decided_at else None
                    ),
                }
                for pact in request.agreements
            ],
        },
    }