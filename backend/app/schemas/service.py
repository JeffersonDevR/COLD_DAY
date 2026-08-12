from pydantic import BaseModel, Field


class ServiceRequestCreate(BaseModel):
    user_id: int
    equipment_id: int
    service_type: str = Field(
        ..., example="installation"
    )  # installation, maintenance, repair
    description: str
    latitude: float = Field(..., example=7.8939)
    longitude: float = Field(..., example=-72.5078)
    budget_offered: float | None = Field(None, example=80000.0)


class TechnicianBidCreate(BaseModel):
    service_request_id: int
    technician_id: int
    price_offered: float
    estimated_time_minutes: int
