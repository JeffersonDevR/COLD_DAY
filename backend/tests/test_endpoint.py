"""Task 6.1 — Smoke tests (sin DB): endpoints respond sin tocar PostgreSQL.

Separa smoke (este archivo + test_security + test_lifecycle + test_*_updates)
de la integración (marcador `integration`, skip si no hay PostGIS — conftest).

Contratos verificados (sin conexión a la DB):
- GET / -> 200 (raíz pública, RF-PILOT-005).
- GET /api/technicians/requests/nearby/ sin token -> 401 (el gate de auth del
  contrato RF-MATCH-004 corre ANTES de tocar la DB; nunca 404/500).
- POST /api/auth/register/client con body vacío -> 422 (validación pydantic).
"""

from fastapi.testclient import TestClient

from main import app


def test_root_endpoint_returns_welcome():
    with TestClient(app) as client:
        response = client.get("/")
        assert response.status_code == 200
        assert "Cold Day" in response.json()["message"]


def test_technician_radar_requires_auth_without_db():
    # El radar técnico (RF-MATCH-004) exige técnico autenticado: sin token el
    # dependency `require_roles("technician")` responde 401 antes de consultar
    # la DB — verificación de contrato sin infraestructura.
    with TestClient(app) as client:
        response = client.get("/api/technicians/requests/nearby/")
        assert response.status_code == 401


def test_register_client_with_empty_body_returns_422():
    # Validación pydantic del contrato de registro (RF-AUTH-001) sin DB.
    with TestClient(app) as client:
        response = client.post("/api/auth/register/client", json={})
        assert response.status_code == 422