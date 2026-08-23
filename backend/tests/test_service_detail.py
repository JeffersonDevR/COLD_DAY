"""Endpoint contract tests for service detail coordinates and access."""

from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api import services
from app.api.deps import get_current_user
from app.core.database import get_db


class _FakeResult:
    def __init__(self, row):
        self._row = row

    def one_or_none(self):
        return self._row


class _FakeSession:
    def __init__(self, row):
        self.row = row

    async def execute(self, _query):
        return _FakeResult(self.row)


def _request(owner_id=1):
    return SimpleNamespace(
        id=7,
        user_id=owner_id,
        status="requested",
        service_type="repair",
        description="No enfría",
        equipment=None,
        created_at=None,
        budget_offered=None,
        diagnosis_observations=None,
        bids=[],
        agreements=[],
        assigned_technician=None,
    )


@pytest.fixture
def app():
    application = FastAPI()
    application.include_router(services.router)
    return application


async def _get_detail(app, *, user_id=1, row=None):
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
        id=user_id, role="client"
    )
    app.dependency_overrides[get_db] = lambda: _FakeSession(
        row or (_request(), 7.8, -72.5)
    )
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.get("/api/services/7")
    app.dependency_overrides.clear()
    return response


@pytest.mark.asyncio
async def test_service_detail_returns_selected_coordinates(app):
    response = await _get_detail(app)

    assert response.status_code == 200
    assert response.json()["latitude"] == 7.8
    assert response.json()["longitude"] == -72.5


@pytest.mark.asyncio
async def test_service_detail_handles_null_location(app):
    response = await _get_detail(app, row=(_request(), None, None))

    assert response.status_code == 200
    assert response.json()["latitude"] is None
    assert response.json()["longitude"] is None


@pytest.mark.asyncio
async def test_service_detail_hides_request_from_other_user(app):
    response = await _get_detail(
        app, user_id=99, row=(_request(owner_id=1), 7.8, -72.5)
    )

    assert response.status_code == 404
