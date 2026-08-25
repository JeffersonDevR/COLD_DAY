from scripts.seed_pilot import CATALOG_DATA, TECHNICIAN_DATA, TECHNICIAN_DOCS


def test_catalog_definitions_cover_sectors_and_technologies():
    assert len(CATALOG_DATA) == 7
    assert {item["name"] for item in CATALOG_DATA} == {
        "Neveras",
        "Cuartos fríos",
        "Aire acondicionado",
        "Lavadoras",
        "Electricidad",
        "Electrónica",
        "Instalación de cámaras",
    }
    assert any(
        "conventional" in item["technologies"] and "inverter" in item["technologies"]
        for item in CATALOG_DATA
    )
    assert all(
        {equipment[0] for equipment in item["equipment"]} <= {"residential", "industrial"}
        for item in CATALOG_DATA
    )


def test_technician_documents_are_derived_from_seed_data():
    assert TECHNICIAN_DOCS == [entry[0] for entry in TECHNICIAN_DATA]
