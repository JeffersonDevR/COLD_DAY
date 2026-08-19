from pydantic import BaseModel, Field


class ServiceRequestCreate(BaseModel):
    # Sin user_id: el dueño sale del token autenticado (RF-SR-001, auth PR1).
    equipment_id: int
    service_type: str = Field(
        ..., example="installation"
    )  # installation, maintenance, repair
    description: str
    latitude: float = Field(..., example=7.8939)
    longitude: float = Field(..., example=-72.5078)
    budget_offered: float | None = Field(None, example=80000.0)


class TechnicianBidCreate(BaseModel):
    # Sin technician_id: el técnico sale del token autenticado (design §API
    # deltas: "POST /api/services/bids/: technician_id del token").
    service_request_id: int
    price_offered: float
    estimated_time_minutes: int
    transport_cost: float
    diagnosis_cost: float