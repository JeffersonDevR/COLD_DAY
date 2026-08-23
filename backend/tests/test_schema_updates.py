from app.schemas.service import TechnicianBidCreate

def test_technician_bid_create_schema_has_new_fields():
    payload = TechnicianBidCreate(
        service_request_id=1,
        price_offered=100.0,
        estimated_time_minutes=30,
        transport_cost=10.0,
        diagnosis_cost=20.0
    )
    assert payload.transport_cost == 10.0
    assert payload.diagnosis_cost == 20.0


def test_coordinates_are_rejected_outside_wgs84_ranges():
    from pydantic import ValidationError
    from app.schemas.service import LocationUpdateCreate, ServiceRequestCreate

    for schema, field, value in [
        (ServiceRequestCreate, "latitude", 91),
        (ServiceRequestCreate, "longitude", 181),
        (LocationUpdateCreate, "latitude", -91),
        (LocationUpdateCreate, "longitude", -181),
    ]:
        payload = {"latitude": 7.8, "longitude": -72.5}
        payload[field] = value
        if schema is ServiceRequestCreate:
            payload["description"] = "x"
        try:
            schema(**payload)
        except ValidationError:
            continue
        raise AssertionError(f"{schema.__name__} accepted invalid {field}")
