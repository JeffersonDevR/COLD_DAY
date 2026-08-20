from app.schemas.service import TechnicianBidCreate

def test_technician_bid_create_schema_has_new_fields():
    # Should fail if schema doesn't have the fields
    payload = TechnicianBidCreate(
        service_request_id=1,
        technician_id=1,
        price_offered=100.0,
        estimated_time_minutes=30,
        transport_cost=10.0,
        diagnosis_cost=20.0
    )
    assert payload.transport_cost == 10.0
    assert payload.diagnosis_cost == 20.0
