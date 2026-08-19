"""Task 3.1 — RED: pure transition table of the PINNED state machine (spec §3).

Unit test WITHOUT database: validates the valid/409 transition contract of the
PINNED machine (requested -> bidding -> diagnosis -> pact_proposed ->
in_progress -> completed; terminal cancelled/completed).

References `app.services.lifecycle` (validate_transition / VALID_TRANSITIONS /
ALL_STATUSES), which does not exist yet -> guaranteed RED on first run.
"""

import pytest
from fastapi import HTTPException

from app.services.lifecycle import (
    ALL_STATUSES,
    CANCELLED,
    COMPLETED,
    VALID_TRANSITIONS,
    validate_transition,
)

# Transiciones válidas de la máquina PINNED (spec §3, tabla "Desde | Hacia").
VALID_TRANSITION_PAIRS = {
    ("requested", "bidding"),        # técnico verified oferta (RF-TEC-006)
    ("bidding", "diagnosis"),        # cliente dueño acepta un bid (RF-SR-003)
    ("requested", "cancelled"),      # cliente dueño cancela (RF-SR-009)
    ("bidding", "cancelled"),        # cliente dueño cancela con ofertas (RF-SR-009)
    ("diagnosis", "pact_proposed"),  # técnico asignado propone pacto (RF-SR-005)
    ("pact_proposed", "in_progress"),  # cliente dueño acepta pacto (RF-SR-006)
    ("pact_proposed", "bidding"),    # cliente dueño rechaza pacto, mercado reabre (RF-SR-007)
    ("in_progress", "completed"),    # técnico asignado finaliza (RF-SR-008)
}

# Todos los estados + 1 inexistente: la guarda también cubre estados
# desconocidos (espec: "desde estado inexistente -> 409").
ALL_TRANSITION_INPUTS = set(ALL_STATUSES) | {"not_a_status"}


def test_valid_transitions_are_accepted():
    """Cada par válido de la máquina PINNED pasa la guarda sin excepción."""
    for current, target in VALID_TRANSITION_PAIRS:
        validate_transition(current, target)


def test_transition_table_matches_the_pinned_spec():
    """La tabla exportada == exactamente los pares válidos de la spec."""
    exported = {
        (current, target) for current, targets in VALID_TRANSITIONS.items() for target in targets
    }
    assert exported == VALID_TRANSITION_PAIRS


def test_illegal_transitions_raise_409():
    """Todo par (estado, destino) no listado en la spec -> HTTPException 409."""
    for current in ALL_TRANSITION_INPUTS:
        for target in ALL_TRANSITION_INPUTS:
            if (current, target) in VALID_TRANSITION_PAIRS:
                continue
            with pytest.raises(HTTPException) as excinfo:
                validate_transition(current, target)
            assert excinfo.value.status_code == 409


def test_terminal_states_are_dead_ends():
    """cancelled/completed no tienen salida: cualquier destino -> 409."""
    for terminal in (COMPLETED, CANCELLED):
        for target in ALL_STATUSES:
            with pytest.raises(HTTPException) as excinfo:
                validate_transition(terminal, target)
            assert excinfo.value.status_code == 409


def test_unknown_state_raises_409():
    with pytest.raises(HTTPException) as excinfo:
        validate_transition("not_a_status", "bidding")
    assert excinfo.value.status_code == 409
