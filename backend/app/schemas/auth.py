"""Schemas de autenticación y perfil (S1 mvp-polish, RF-AUTH-001..008)."""

from pydantic import BaseModel, ConfigDict, Field


class RegisterClient(BaseModel):
    full_name: str = Field(min_length=2, max_length=100)
    document: str = Field(min_length=3, max_length=20)
    phone: str = Field(min_length=5, max_length=30)
    password: str


class RegisterTechnician(RegisterClient):
    specialty: str = Field(min_length=2, max_length=100)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class LoginRequest(BaseModel):
    document: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    role: str
    user_id: int


class UserUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=100)
    phone: str | None = Field(default=None, min_length=5, max_length=30)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    full_name: str
    document: str
    phone: str
    role: str
