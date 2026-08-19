"""Endpoints del dashboard admin (S5 mvp-polish, RF-ADM-001..008).

- GET  /api/admin/kpis                       -> KPIs del piloto (RF-ADM-002)
- GET  /api/admin/users/clients              -> lista de clientes (RF-ADM-003)
- GET  /api/admin/users/technicians          -> lista de técnicos (RF-ADM-004)
- GET  /api/admin/requests?status=           -> monitoreo con filtro (RF-ADM-006)
- POST /api/admin/technicians/{id}/verify    -> pending -> verified (RF-ADM-005)
- POST /api/admin/technicians/{id}/reject    -> pending -> rejected, motivo
       obligatorio 422 (RF-TEC-003); estado que no sea pending -> 409 (RF-ADM-008)

Todos los endpoints exigen rol admin -> 403 para cualquier otro rol (RF-ADM-007).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_roles
from app.core.database import get_db
from app.models.service import Equipment, ServiceRequest, Technician
from app.models.user import User
from app.schemas.admin import (
    AdminActionResponse,
    AdminRequestOut,
    ClientOut,
    KpisResponse,
    RejectRequest,
    TechnicianOut,
)

router = APIRouter(prefix="/api/admin", tags=["Admin"])

# Estados de la máquina PINNED (spec §3): el desglose devuelve todos con 0 por
# defecto para que el dashboard no dependa de qué estados existen en la DB.
REQUEST_STATUSES = [
    "requested",
    "bidding",
    "diagnosis",
    "pact_proposed",
    "in_progress",
    "completed",
    "cancelled",
]


@router.get("/kpis", response_model=KpisResponse)
async def get_kpis(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles("admin")),
) -> KpisResponse:
    """KPIs del piloto: totales de clientes/técnicos, pendientes y desglose."""
    total_clients = (
        await db.execute(
            select(func.count()).select_from(User).where(User.role == "client")
        )
    ).scalar_one()
    total_technicians = (
        await db.execute(select(func.count()).select_from(Technician))
    ).scalar_one()
    pending_technicians = (
        await db.execute(
            select(func.count())
            .select_from(Technician)
            .where(Technician.verification_status == "pending")
        )
    ).scalar_one()

    rows = (
        await db.execute(
            select(ServiceRequest.status, func.count()).group_by(
                ServiceRequest.status
            )
        )
    ).all()
    by_status = {s: 0 for s in REQUEST_STATUSES}
    for request_status, count in rows:
        by_status[request_status] = count

    return KpisResponse(
        total_clients=total_clients,
        total_technicians=total_technicians,
        pending_technicians=pending_technicians,
        requests_by_status=by_status,
    )


@router.get("/users/clients")
async def list_clients(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles("admin")),
):
    """Lista de clientes: nombre, documento, teléfono, fecha (RF-ADM-003)."""
    clients = (
        (
            await db.execute(
                select(User)
                .where(User.role == "client")
                .order_by(User.created_at.desc())
            )
        )
        .scalars()
        .all()
    )
    return {
        "clients": [ClientOut.model_validate(client) for client in clients]
    }


@router.get("/users/technicians")
async def list_technicians(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles("admin")),
):
    """Lista de técnicos: nombre, especialidad, estado, calificación
    (RF-ADM-004). El dashboard Flutter arma la cola filtrando `pending`."""
    technicians = (
        (
            await db.execute(
                select(Technician).order_by(Technician.name)
            )
        )
        .scalars()
        .all()
    )
    return {
        "technicians": [
            TechnicianOut.model_validate(technician) for technician in technicians
        ]
    }


@router.get("/requests")
async def list_requests(
    status: str | None = None,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles("admin")),
):
    """Monitoreo de solicitudes con filtro opcional por estado (RF-ADM-006).

    Devuelve contexto legible para el admin: equipo y cliente, fecha desc.
    """
    query = (
        select(ServiceRequest, Equipment.name, User.full_name)
        .join(Equipment, Equipment.id == ServiceRequest.equipment_id)
        .join(User, User.id == ServiceRequest.user_id)
        .order_by(ServiceRequest.created_at.desc())
    )
    if status is not None:
        query = query.where(ServiceRequest.status == status)
    rows = (await db.execute(query)).all()

    return {
        "requests": [
            AdminRequestOut(
                id=request.id,
                status=request.status,
                service_type=request.service_type,
                description=request.description,
                equipment_name=equipment_name,
                client_name=client_name,
                created_at=request.created_at,
            )
            for request, equipment_name, client_name in rows
        ]
    }


async def _load_pending_technician(
    db: AsyncSession, technician_id: int
) -> Technician:
    """Carga el técnico; 404 si no existe, 409 si no está `pending` (RF-ADM-008)."""
    technician = await db.get(Technician, technician_id)
    if technician is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Técnico no encontrado"
        )
    if technician.verification_status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="El técnico no está pendiente de verificación",
        )
    return technician


@router.post("/technicians/{technician_id}/verify", response_model=AdminActionResponse)
async def verify_technician(
    technician_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles("admin")),
) -> AdminActionResponse:
    """Aprueba a un técnico de la cola: pending -> verified (RF-ADM-005)."""
    technician = await _load_pending_technician(db, technician_id)
    technician.verification_status = "verified"
    technician.rejection_reason = None
    await db.commit()
    return AdminActionResponse(
        message="Técnico verificado",
        technician_id=technician_id,
        verification_status="verified",
    )


@router.post("/technicians/{technician_id}/reject", response_model=AdminActionResponse)
async def reject_technician(
    technician_id: int,
    payload: RejectRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles("admin")),
) -> AdminActionResponse:
    """Rechaza a un técnico de la cola: pending -> rejected + motivo obligatorio.

    Sin `reason` (o vacío/espacios) -> 422 (RF-TEC-003). Estado no `pending`
    -> 409 (RF-ADM-008).
    """
    technician = await _load_pending_technician(db, technician_id)
    reason = payload.reason.strip()
    if not reason:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="El motivo del rechazo es obligatorio",
        )
    technician.verification_status = "rejected"
    technician.rejection_reason = reason
    await db.commit()
    return AdminActionResponse(
        message="Técnico rechazado",
        technician_id=technician_id,
        verification_status="rejected",
    )