"""Calificaciones post-servicio (S4 ratings, RF-RAT-001..006).

El redondeo vive en funciones PURAS (unit-testable sin DB, design §Estrategia
de testing): `round_global_score` (RF-RAT-003) y `average_rounded_1decimal`
(RF-RAT-005). `create_review` orquesta la evaluación con la validación de
dominio y el recálculo atómico de `Technician.rating`.
"""

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.service import Review, ServiceRequest, Technician
from app.models.user import User

COMPLETED = "completed"

ALREADY_REVIEWED_DETAIL = "Este servicio ya fue calificado"
NOT_COMPLETED_DETAIL = "El servicio no está completado"
NO_TECHNICIAN_DETAIL = "El servicio no tiene técnico asignado"


def round_global_score(punctuality: int, quality: int, professionalism: int) -> float:
    """Puntaje global = promedio simple de las 3 sub-dimensiones a 1 decimal.

    RF-RAT-003. Ejemplo spec: 5/4/5 -> 14/3 = 4.666... -> 4.7.
    """
    return round((punctuality + quality + professionalism) / 3.0, 1)


def average_rounded_1decimal(scores: list[float]) -> float:
    """Promedio de puntajes globales redondeado a 1 decimal (RF-RAT-005).

    Sin evaluaciones -> 0.0 (rating inicial del técnico).
    """
    if not scores:
        return 0.0
    return round(sum(scores) / len(scores), 1)


async def create_review(
    db: AsyncSession,
    *,
    request_id: int,
    client: User,
    punctuality: int,
    quality: int,
    professionalism: int,
    comment: str | None,
) -> tuple[Review, float]:
    """RF-RAT-001..005: el cliente DUEÑO evalúa una solicitud COMPLETADA.

    Validaciones (orden deliberado, spec escenarios):
    - solicitud inexistente -> 404;
    - evaluador distinto del dueño -> 403 (RF-RAT-001: "cliente dueño");
    - solicitud no `completed` -> 422 (RF-RAT-006);
    - sin técnico asignado -> 422 (defensivo, un completed siempre lo tiene);
    - duplicado -> 409 (RF-RAT-004: constraint único por request_id, con
      pre-check y catch de IntegrityError para la carrera).

    Al insertar la evaluación recalcula `Technician.rating` (RF-RAT-005) como
    promedio de los puntajes globales a 1 decimal, en el MISMO commit.
    Returns (review, technician_rating_nuevo).
    """
    req = await db.get(ServiceRequest, request_id)
    if req is None:
        raise HTTPException(status_code=404, detail="Service request not found")

    if req.user_id != client.id:
        raise HTTPException(
            status_code=403, detail="Solo el cliente dueño puede calificar"
        )

    if req.status != COMPLETED:
        raise HTTPException(status_code=422, detail=NOT_COMPLETED_DETAIL)

    if req.assigned_technician_id is None:
        raise HTTPException(status_code=422, detail=NO_TECHNICIAN_DETAIL)

    existing = (
        await db.execute(
            select(Review).where(Review.service_request_id == request_id)
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=409, detail=ALREADY_REVIEWED_DETAIL)

    global_score = round_global_score(punctuality, quality, professionalism)

    # Recálculo (RF-RAT-005): promedio de TODOS los puntajes del técnico. La
    # consulta corre ANTES de db.add: autoflush de SQLAlchemy incluiría la nueva
    # Review pendiente y el global se contaría dos veces (4.3 en vez de 4.5).
    scores = (
        await db.execute(
            select(Review.global_score).where(
                Review.technician_id == req.assigned_technician_id
            )
        )
    ).scalars().all()

    review = Review(
        service_request_id=request_id,
        client_id=client.id,
        technician_id=req.assigned_technician_id,
        punctuality=punctuality,
        quality=quality,
        professionalism=professionalism,
        comment=comment,
        global_score=global_score,
    )
    db.add(review)

    tech = await db.get(Technician, req.assigned_technician_id)
    new_rating = average_rounded_1decimal(list(scores) + [global_score])
    tech.rating = new_rating

    try:
        await db.commit()
    except IntegrityError:
        # Carrera: otra evaluación para la misma solicitud ganó el constraint.
        await db.rollback()
        raise HTTPException(status_code=409, detail=ALREADY_REVIEWED_DETAIL)

    await db.refresh(review)
    return review, new_rating