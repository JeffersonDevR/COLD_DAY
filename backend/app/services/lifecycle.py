"""Máquina de estados PINNED del vertical del Pacto (S3 mvp-polish).

Un solo escritor por transición: cada operación corre en SU propia transacción
con `SELECT ... FOR UPDATE` sobre la fila service_requests y muta bids/pacts en
el MISMO commit (design §Máquina de estados). Estados y transiciones: spec §3.

La guarda central `validate_transition` es PURA (sin DB) para poder testearla en
unit sin infraestructura; las transiciones asíncronas la usan siempre.
"""

from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.service import (
    ServiceAgreement,
    ServiceRequest,
    Technician,
    TechnicianBid,
)

# --- Estados PINNED de la solicitud (spec §3) --------------------------------
REQUESTED = "requested"
BIDDING = "bidding"
DIAGNOSIS = "diagnosis"
PACT_PROPOSED = "pact_proposed"
IN_PROGRESS = "in_progress"
COMPLETED = "completed"
CANCELLED = "cancelled"

ALL_STATUSES = frozenset(
    {REQUESTED, BIDDING, DIAGNOSIS, PACT_PROPOSED, IN_PROGRESS, COMPLETED, CANCELLED}
)

# TechnicianBid.status
BID_PENDING = "pending"
BID_ACCEPTED = "accepted"
BID_REJECTED = "rejected"

# ServiceAgreement.status
PACT_PROPOSED_STATUS = "proposed"
PACT_ACCEPTED_STATUS = "accepted"
PACT_REJECTED_STATUS = "rejected"

#: Tabla de transiciones válidas de la máquina PINNED: estado actual -> destinos.
VALID_TRANSITIONS: dict[str, set[str]] = {
    REQUESTED: {BIDDING, CANCELLED},
    BIDDING: {DIAGNOSIS, CANCELLED},
    DIAGNOSIS: {PACT_PROPOSED},
    PACT_PROPOSED: {IN_PROGRESS, BIDDING},
    IN_PROGRESS: {COMPLETED},
    COMPLETED: set(),
    CANCELLED: set(),
}

CONFLICT_DETAIL = "Transición no permitida para el estado actual"


def validate_transition(current: str, target: str) -> None:
    """Lanza 409 si `current -> target` no pertenece a la máquina PINNED.

    Cubre doble aceptación (fuera de bidding/pact_proposed), cancelación tardía
    (desde diagnosis en adelante), finalización anticipada, estados inexistentes
    y transiciones de estados terminales (spec §3 "Reglas de invariancia").
    """
    if target not in VALID_TRANSITIONS.get(current, set()):
        raise HTTPException(status_code=409, detail=CONFLICT_DETAIL)


# --- Acceso de un solo escritor (design §Máquina de estados) -----------------

async def _lock_request(db: AsyncSession, request_id: int) -> ServiceRequest | None:
    """SELECT ... FOR UPDATE: bloquea la fila de la solicitud para el escritor."""
    result = await db.execute(
        select(ServiceRequest)
        .where(ServiceRequest.id == request_id)
        .with_for_update()
    )
    return result.scalar_one_or_none()


async def _load_owner_request(
    db: AsyncSession, request_id: int, user_id: int
) -> ServiceRequest:
    """Carga la solicitud y valida propiedad (RF-SR-012): ajena -> 404.

    404 (no 403) para no revelar la existencia de solicitudes ajenas.
    """
    req = await _lock_request(db, request_id)
    if req is None or req.user_id != user_id:
        raise HTTPException(status_code=404, detail="Service request not found")
    return req


def _validate_assigned(req: ServiceRequest, technician: Technician) -> None:
    if req.assigned_technician_id != technician.id:
        raise HTTPException(status_code=403, detail="No eres el técnico asignado")


async def _load_technician_action(
    db: AsyncSession,
    request_id: int,
    technician: Technician,
    target_status: str,
) -> ServiceRequest:
    """Carga la solicitud para una acción del técnico asignado.

    Orden deliberado: primero la guarda de transición (409, spec "Transición
    ilegal" — completar desde `requested` -> 409), después el vínculo de
    asignación (403, aislamiento de propiedad). Así el escenario de transición
    ilegal gana aunque el técnico no sea el asignado.
    """
    req = await _lock_request(db, request_id)
    if req is None:
        raise HTTPException(status_code=404, detail="Service request not found")
    validate_transition(req.status, target_status)
    _validate_assigned(req, technician)
    return req


# --- Transiciones (cada una en su propia transacción atómica) ----------------

async def create_bid(
    db: AsyncSession,
    *,
    technician: Technician,
    request_id: int,
    price_offered: float,
    estimated_time_minutes: int,
    transport_cost: float,
    diagnosis_cost: float,
) -> TechnicianBid:
    """Crea un bid (RF-TEC-006/007, RF-SR-002).

    Valida (else 409/403): técnico `verified`+`free`, solicitud en
    `requested`/`bidding`, un solo bid por (request, technician). Atómico:
    si la solicitud venía de `requested`, pasa a `bidding` en el mismo commit.
    """
    if technician.verification_status != "verified":
        raise HTTPException(
            status_code=403,
            detail="El técnico debe estar verificado para ofertar",
        )
    if technician.availability != "free":
        raise HTTPException(status_code=409, detail="El técnico no está disponible")

    req = await _lock_request(db, request_id)
    if req is None:
        raise HTTPException(status_code=404, detail="Service request not found")
    if req.status not in (REQUESTED, BIDDING):
        raise HTTPException(status_code=409, detail=CONFLICT_DETAIL)

    existing = (
        await db.execute(
            select(TechnicianBid).where(
                TechnicianBid.service_request_id == request_id,
                TechnicianBid.technician_id == technician.id,
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=409, detail="Ya ofertaste en esta solicitud")

    bid = TechnicianBid(
        service_request_id=request_id,
        technician_id=technician.id,
        price_offered=price_offered,
        estimated_time_minutes=estimated_time_minutes,
        transport_cost=transport_cost,
        diagnosis_cost=diagnosis_cost,
        status=BID_PENDING,
    )
    db.add(bid)
    if req.status == REQUESTED:
        req.status = BIDDING  # primer bid abre el mercado (máquina PINNED)
    await db.commit()
    await db.refresh(bid)
    return bid


async def accept_bid(
    db: AsyncSession, *, request_id: int, bid_id: int, user_id: int
) -> ServiceRequest:
    """RF-SR-003: el cliente dueño acepta un bid desde `bidding`.

    Atómico (un commit): bid -> accepted, resto de bids pendientes -> rejected,
    request -> diagnosis, assigned_technician_id = técnico del bid aceptado.
    """
    req = await _load_owner_request(db, request_id, user_id)
    validate_transition(req.status, DIAGNOSIS)  # solo desde bidding (doble -> 409)

    bid = await db.get(TechnicianBid, bid_id)
    if bid is None or bid.service_request_id != request_id:
        raise HTTPException(status_code=404, detail="Bid not found")
    if bid.status != BID_PENDING:
        raise HTTPException(status_code=409, detail="El bid ya fue resuelto")

    bid.status = BID_ACCEPTED
    competitors = await db.execute(
        select(TechnicianBid).where(
            TechnicianBid.service_request_id == request_id,
            TechnicianBid.id != bid_id,
            TechnicianBid.status == BID_PENDING,
        )
    )
    for other in competitors.scalars():
        other.status = BID_REJECTED

    req.status = DIAGNOSIS
    req.assigned_technician_id = bid.technician_id
    await db.commit()
    await db.refresh(req)
    return req


async def register_diagnosis(
    db: AsyncSession,
    *,
    request_id: int,
    technician: Technician,
    observations: str,
) -> ServiceRequest:
    """RF-SR-004: el técnico asignado registra las observaciones del diagnóstico.

    No cambia el estado (la transición a pact_proposed la dispara el pacto);
    solo persiste las observaciones en la solicitud.
    """
    req = await _load_technician_action(db, request_id, technician, PACT_PROPOSED)

    req.diagnosis_observations = observations
    await db.commit()
    await db.refresh(req)
    return req


async def create_agreement(
    db: AsyncSession,
    *,
    request_id: int,
    technician: Technician,
    labor_cost: float,
    transport_cost: float,
    diagnosis_cost: float,
    observations: str | None,
) -> ServiceAgreement:
    """RF-SR-005: pacto con desglose; diagnosis -> pact_proposed (atómico).

    `total` = labor + transport + diagnosis (el price_offered del bid es solo
    informativo y NO entra en el total, design §Preguntas abiertas).
    """
    req = await _load_technician_action(db, request_id, technician, PACT_PROPOSED)

    pact = ServiceAgreement(
        service_request_id=request_id,
        technician_id=technician.id,
        labor_cost=labor_cost,
        transport_cost=transport_cost,
        diagnosis_cost=diagnosis_cost,
        total=labor_cost + transport_cost + diagnosis_cost,
        observations=observations,
        status=PACT_PROPOSED_STATUS,
    )
    db.add(pact)
    req.status = PACT_PROPOSED
    await db.commit()
    await db.refresh(pact)
    return pact


async def accept_pact(
    db: AsyncSession, *, request_id: int, agreement_id: int, user_id: int
) -> ServiceRequest:
    """RF-SR-006: el cliente dueño acepta el pacto desde `pact_proposed`.

    Atómico: pacto -> accepted; cualquier otro pacto propuesto -> rejected;
    request -> in_progress.
    """
    req = await _load_owner_request(db, request_id, user_id)
    validate_transition(req.status, IN_PROGRESS)  # solo desde pact_proposed

    pact = await db.get(ServiceAgreement, agreement_id)
    if pact is None or pact.service_request_id != request_id:
        raise HTTPException(status_code=404, detail="Agreement not found")
    if pact.status != PACT_PROPOSED_STATUS:
        raise HTTPException(status_code=409, detail="El pacto ya fue resuelto")

    now = datetime.now(timezone.utc)
    pact.status = PACT_ACCEPTED_STATUS
    pact.decided_at = now

    other_pacts = await db.execute(
        select(ServiceAgreement).where(
            ServiceAgreement.service_request_id == request_id,
            ServiceAgreement.id != agreement_id,
            ServiceAgreement.status == PACT_PROPOSED_STATUS,
        )
    )
    for other in other_pacts.scalars():
        other.status = PACT_REJECTED_STATUS
        other.decided_at = now

    req.status = IN_PROGRESS
    await db.commit()
    await db.refresh(req)
    return req


async def reject_pact(
    db: AsyncSession, *, request_id: int, agreement_id: int, user_id: int
) -> ServiceRequest:
    """RF-SR-007: rechazo del pacto reabre el mercado.

    Atómico: pacto -> rejected (histórico); TODOS los bids -> pending;
    request -> bidding.
    """
    req = await _load_owner_request(db, request_id, user_id)
    validate_transition(req.status, BIDDING)  # solo desde pact_proposed

    pact = await db.get(ServiceAgreement, agreement_id)
    if pact is None or pact.service_request_id != request_id:
        raise HTTPException(status_code=404, detail="Agreement not found")
    if pact.status != PACT_PROPOSED_STATUS:
        raise HTTPException(status_code=409, detail="El pacto ya fue resuelto")

    pact.status = PACT_REJECTED_STATUS
    pact.decided_at = datetime.now(timezone.utc)

    bids = (
        await db.execute(
            select(TechnicianBid).where(
                TechnicianBid.service_request_id == request_id
            )
        )
    ).scalars().all()
    for bid in bids:
        bid.status = BID_PENDING  # mercado reabre: TODOS a pending

    req.status = BIDDING
    await db.commit()
    await db.refresh(req)
    return req


async def cancel_request(
    db: AsyncSession, *, request_id: int, user_id: int
) -> ServiceRequest:
    """RF-SR-009: cancelación solo desde requested/bidding (pre-asignación).

    Atómico: request -> cancelled; bids pendientes -> rejected.
    """
    req = await _load_owner_request(db, request_id, user_id)
    validate_transition(req.status, CANCELLED)  # diagnosis en adelante -> 409

    bids = (
        await db.execute(
            select(TechnicianBid).where(
                TechnicianBid.service_request_id == request_id,
                TechnicianBid.status == BID_PENDING,
            )
        )
    ).scalars().all()
    for bid in bids:
        bid.status = BID_REJECTED

    req.status = CANCELLED
    await db.commit()
    await db.refresh(req)
    return req


async def complete_request(
    db: AsyncSession, *, request_id: int, technician: Technician
) -> ServiceRequest:
    """RF-SR-008: el técnico asignado finaliza desde `in_progress`."""
    req = await _load_technician_action(db, request_id, technician, COMPLETED)

    req.status = COMPLETED
    await db.commit()
    await db.refresh(req)
    return req
