"""Schemas del dashboard admin (S5 mvp-polish, RF-ADM-001..008)."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class KpisResponse(BaseModel):
    """KPIs del piloto (RF-ADM-002): totales + desglose de solicitudes por estado."""

    total_clients: int
    total_technicians: int
    pending_technicians: int
    requests_by_status: dict[str, int]


class ClientOut(BaseModel):
    """Fila de la lista de clientes (RF-ADM-003)."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    full_name: str
    document: str
    phone: str
    created_at: datetime


class TechnicianOut(BaseModel):
    """Fila de la lista de técnicos (RF-ADM-004) y de la cola de verificación."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    specialty: str | None
    verification_status: str
    rating: float


class AdminRequestOut(BaseModel):
    """Fila del monitoreo de solicitudes (RF-ADM-006) con contexto legible."""

    id: int
    status: str
    service_type: str
    description: str
    equipment_name: str | None
    client_name: str
    created_at: datetime


class RejectRequest(BaseModel):
    """Motivo del rechazo (RF-TEC-003): obligatorio -> 422 si falta o vacío."""

    reason: str = Field(min_length=1, max_length=500)


class AdminActionResponse(BaseModel):
    """Respuesta de verify/reject sobre la cola (RF-ADM-005)."""

    message: str
    technician_id: int
    verification_status: str
