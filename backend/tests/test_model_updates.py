import pytest
from app.models.service import TechnicianBid

def test_technician_bid_has_new_fields():
    bid = TechnicianBid(transport_cost=10.0, diagnosis_cost=20.0)
    assert bid.transport_cost == 10.0
    assert bid.diagnosis_cost == 20.0
    assert isinstance(bid.transport_cost, float)
    assert isinstance(bid.diagnosis_cost, float)
