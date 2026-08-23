from pydantic import BaseModel, Field


class ServiceRequestCreate(BaseModel):
    # Sin user_id: el dueño sale del token autenticado (RF-SR-001, auth PR1).
    equipment_id: int | None = None
    category_hint: str | None = None
    service_type: str = "repair"  # installation, maintenance, repair
    description: str
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    budget_offered: float | None = None


class TechnicianBidCreate(BaseModel):
    # Sin technician_id: el técnico sale del token autenticado (design §API
    # deltas: "POST /api/services/bids/: technician_id del token").
    service_request_id: int
    price_offered: float
    estimated_time_minutes: int
    transport_cost: float
    diagnosis_cost: float


class DiagnosisCreate(BaseModel):
    """Observaciones del diagnóstico del técnico asignado (RF-SR-004)."""

    observations: str = Field(min_length=1, max_length=2000)


class AgreementCreate(BaseModel):
    """Desglose del Pacto de Servicio (RF-SR-005).

    `labor_cost` + `transport_cost` + `diagnosis_cost`; el backend calcula
    `total` = suma. Costos negativos -> 422 con el campo señalado (ge=0).
    """

    labor_cost: float = Field(..., ge=0)
    transport_cost: float = Field(..., ge=0)
    diagnosis_cost: float = Field(..., ge=0)
    observations: str | None = Field(None, max_length=2000)


class ReviewCreate(BaseModel):
    """Evaluación post-servicio del cliente dueño (RF-RAT-002).

    Tres sub-dimensiones 1-5 + comentario OPCIONAL <= 1000 caracteres.
    Fuera de rango / demasiado largo -> 422 por campo (Pydantic).
    """

    punctuality: int = Field(..., ge=1, le=5)
    quality: int = Field(..., ge=1, le=5)
    professionalism: int = Field(..., ge=1, le=5)
    comment: str | None = Field(None, max_length=1000)


class TechnicianServiceCreate(BaseModel):
    category_id: int
    service_types: list[str] = ['repair']
    sector: str = 'both'

class TechnicianServiceOut(BaseModel):
    id: int
    category_id: int
    category_name: str | None = None
    service_types: list[str]
    sector: str
    active: bool

class LocationUpdateCreate(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
