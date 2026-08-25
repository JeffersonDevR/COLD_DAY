#!/usr/bin/env python3
"""Seed piloto idempotente (S6 mvp-polish, RF-AUTH-008 / RF-PILOT-003).

Crea los clientes y técnicos definidos abajo, más 1 admin y el catálogo MVP. Re-ejecutable:
la segunda corrida no duplica nada (los documentos son fijos y únicos).
A diferencia de seed_admin.py (PR1), NO corre create_all: el esquema lo
gobierna Alembic (RF-PILOT-001) — ejecutar `alembic upgrade head` primero.

Uso:
  cd backend && .venv/bin/python scripts/seed_pilot.py          # seed
  cd backend && .venv/bin/python scripts/seed_pilot.py --teardown  # lo revierte

Teardown: elimina EXACTAMENTE los documentos del seed (2000000001..05,
3000000001..05, 1000000001) y sus dependencias (auth_tokens, technicians).
"""

import argparse
import asyncio
import sys
from dataclasses import dataclass, field
from pathlib import Path

# Permite ejecutar el script directo desde backend/ sin PYTHONPATH
# (cd backend && .venv/bin/python scripts/seed_pilot.py).
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import delete, select  # noqa: E402

from app.core.database import AsyncSessionLocal
from app.core.security import hash_password
from app.models.service import (
    Equipment,
    EquipmentCategory,
    LocationUpdate,
    Review,
    ServiceAgreement,
    ServiceRequest,
    Technician,
    TechnicianBid,
)
from app.models.user import AuthToken, User

# Ubicación del piloto: Cúcuta (Colombia), con offsets para que el radar
# (ST_DWithin, RF-MATCH-001) vea técnicos cercanos.
CUCUTA_LAT, CUCUTA_LON = 7.8939, -72.5078

CLIENT_DOCS = [f"200000000{i}" for i in range(1, 6)]
TECHNICIAN_DATA = [
    ("3000000001", "Ana Teresa Ruiz", "Neveras", 7.8939, -72.5078),
    ("3000000002", "Carlos Mendoza", "Aire acondicionado", 7.8980, -72.5100),
    ("3000000003", "Luis Fernando Paez", "Cuartos fríos", 7.8900, -72.5000),
    ("3000000004", "Martha Cecilia Diaz", "Electricidad", 7.8950, -72.5150),
    ("3000000005", "Jorge Eduardo Rojas", "Lavadoras", 7.8880, -72.5050),
]
TECHNICIAN_DOCS = [entry[0] for entry in TECHNICIAN_DATA]
ADMIN_DOC = "1000000001"
SEED_DOCS = [*CLIENT_DOCS, *TECHNICIAN_DOCS, ADMIN_DOC]

# Names are the ownership key for this additive seed. Existing rows with the
# same name are preserved, including their icon/technology metadata.
CATALOG_DATA = [
    {
        "name": "Neveras",
        "icon": "kitchen",
        "technologies": ["conventional", "inverter"],
        "equipment": [
            ("residential", "Nevera clásica", "Nevera convencional"),
            ("residential", "Nevera inverter", "Nevera inverter"),
            ("industrial", "Nevera comercial", "Nevera comercial / vitrina"),
        ],
    },
    {
        "name": "Cuartos fríos",
        "icon": "snow",
        "technologies": ["conventional", "inverter"],
        "equipment": [("industrial", "Cámara de frío", "Cámara para conservación")],
    },
    {
        "name": "Aire acondicionado",
        "icon": "air_wave",
        "technologies": ["conventional", "inverter"],
        "equipment": [
            ("residential", "Split", "Aire acondicionado split residencial"),
            ("residential", "Ventana", "Aire acondicionado de ventana"),
            ("industrial", "Cassette", "Aire acondicionado cassette"),
            ("industrial", "Chiller", "Sistema de agua helada"),
        ],
    },
    {
        "name": "Lavadoras",
        "icon": "laundry",
        "technologies": ["conventional", "inverter"],
        "equipment": [
            ("residential", "Lavadora doméstica", "Lavadora de uso doméstico"),
            ("industrial", "Lavadora industrial", "Lavadora de uso industrial"),
        ],
    },
    {
        "name": "Electricidad",
        "icon": "electricity",
        "technologies": [],
        "equipment": [
            ("residential", "Electricidad residencial", "Instalación y reparación"),
            ("industrial", "Electricidad industrial", "Instalación y reparación"),
        ],
    },
    {
        "name": "Electrónica",
        "icon": "devices",
        "technologies": [],
        "equipment": [
            ("residential", "TV y audio", "Electrónica de hogar"),
            ("industrial", "Electrónica industrial", "Electrónica de uso industrial"),
        ],
    },
    {
        "name": "Instalación de cámaras",
        "icon": "videocam",
        "technologies": [],
        "equipment": [
            ("residential", "Cámaras CCTV", "Instalación de cámaras"),
            ("industrial", "Cámaras CCTV", "Instalación de cámaras"),
        ],
    },
]

PILOT_PASSWORD = "PilotoCold456"  # cumple la política (may/min/dígito, >=8)


@dataclass
class SeedSummary:
    clients_created: int = 0
    clients_existing: int = 0
    technicians_created: int = 0
    technicians_existing: int = 0
    admin_created: int = 0
    admin_existing: int = 0
    catalog_categories_created: int = 0
    catalog_categories_existing: int = 0
    catalog_equipment_created: int = 0
    catalog_equipment_existing: int = 0
    notes: list[str] = field(default_factory=list)

    def render(self) -> str:
        return (
            "Seed piloto: "
            f"{self.clients_created} clientes creados / {self.clients_existing} existentes · "
            f"{self.technicians_created} técnicos creados / {self.technicians_existing} existentes · "
            f"{self.admin_created} admin creado / {self.admin_existing} existente"
        )


async def _user_exists(session, document: str) -> bool:
    return (
        await session.execute(select(User.id).where(User.document == document))
    ).scalar_one_or_none() is not None


async def seed_pilot() -> SeedSummary:
    summary = SeedSummary()
    async with AsyncSessionLocal() as session:
        # --- Clientes (rol client) -------------------------------------------
        for doc in CLIENT_DOCS:
            if await _user_exists(session, doc):
                summary.clients_existing += 1
                continue
            session.add(
                User(
                    full_name=f"Cliente Piloto {doc[-2:]}",
                    document=doc,
                    phone=f"31100000{doc[-2:]}",
                    password_hash=await hash_password(PILOT_PASSWORD),
                    role="client",
                )
            )
            summary.clients_created += 1

        # --- Técnicos (rol technician + perfil Technician pending) -----------
        for doc, name, specialty, lat, lon in TECHNICIAN_DATA:
            if await _user_exists(session, doc):
                summary.technicians_existing += 1
                continue
            user = User(
                full_name=name,
                document=doc,
                phone=f"31200000{doc[-2:]}",
                password_hash=await hash_password(PILOT_PASSWORD),
                role="technician",
            )
            session.add(user)
            await session.flush()  # user.id para el perfil Technician
            session.add(
                Technician(
                    user_id=user.id,
                    name=name,
                    specialty=specialty,
                    location=f"POINT({lon} {lat})",  # WKT, como register/technician
                    verification_status="pending",  # pendientes de verificación
                    availability="free",
                )
            )
            summary.technicians_created += 1

        # --- Admin (mismo documento que seed_admin.py, PR1) ------------------
        if await _user_exists(session, ADMIN_DOC):
            summary.admin_existing += 1
        else:
            session.add(
                User(
                    full_name="Administrador ColdDay",
                    document=ADMIN_DOC,
                    phone="3000000000",
                    password_hash=await hash_password("AdminPiloto123"),
                    role="admin",
                )
            )
            summary.admin_created += 1

        # --- Catálogo MVP (aditivo, sin precios) ------------------------------
        for category_data in CATALOG_DATA:
            category = (
                await session.execute(
                    select(EquipmentCategory).where(
                        EquipmentCategory.name == category_data["name"]
                    )
                )
            ).scalar_one_or_none()
            if category is None:
                category = EquipmentCategory(
                    name=category_data["name"],
                    icon=category_data["icon"],
                    technologies=category_data["technologies"],
                )
                session.add(category)
                await session.flush()
                summary.catalog_categories_created += 1
            else:
                summary.catalog_categories_existing += 1

            for sector, name, description in category_data["equipment"]:
                equipment = (
                    await session.execute(
                        select(Equipment.id).where(
                            Equipment.category_id == category.id,
                            Equipment.sector == sector,
                            Equipment.name == name,
                        )
                    )
                ).scalar_one_or_none()
                if equipment is None:
                    session.add(
                        Equipment(
                            category_id=category.id,
                            sector=sector,
                            name=name,
                            description=description,
                        )
                    )
                    summary.catalog_equipment_created += 1
                else:
                    summary.catalog_equipment_existing += 1

        await session.commit()
    summary.notes.append("técnicos en estado pending (verificarlos desde el panel admin)")
    return summary


async def teardown_pilot() -> str:
    """Elimina los documentos del seed y sus dependencias (FK order)."""
    async with AsyncSessionLocal() as session:
        doc_tuple = tuple(SEED_DOCS)
        user_ids = (
            await session.execute(
                select(User.id).where(User.document.in_(doc_tuple))
            )
        ).scalars().all()
        if not user_ids:
            await session.commit()
            return "Teardown: no había usuarios del seed que eliminar."
        # FK order: remove any dependent records belonging to these known seed
        # users, then auth tokens/technicians/users. This remains safe if pilot
        # users were used for manual smoke data after the seed was run.
        request_ids = (
            await session.execute(
                select(ServiceRequest.id).where(ServiceRequest.user_id.in_(user_ids))
            )
        ).scalars().all()
        if request_ids:
            await session.execute(
                delete(LocationUpdate).where(
                    LocationUpdate.service_request_id.in_(request_ids)
                )
            )
            await session.execute(
                delete(Review).where(Review.service_request_id.in_(request_ids))
            )
            await session.execute(
                delete(ServiceAgreement).where(
                    ServiceAgreement.service_request_id.in_(request_ids)
                )
            )
            await session.execute(
                delete(TechnicianBid).where(
                    TechnicianBid.service_request_id.in_(request_ids)
                )
            )
            await session.execute(
                delete(ServiceRequest).where(ServiceRequest.id.in_(request_ids))
            )
        await session.execute(delete(AuthToken).where(AuthToken.user_id.in_(user_ids)))
        await session.execute(delete(Technician).where(Technician.user_id.in_(user_ids)))
        await session.execute(delete(User).where(User.id.in_(user_ids)))
        await session.commit()
    return f"Teardown: {len(user_ids)} usuarios del seed eliminados."


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed piloto ColdDay con usuarios y catálogo MVP")
    parser.add_argument("--teardown", action="store_true", help="Elimina los usuarios del seed")
    args = parser.parse_args()
    if args.teardown:
        print(asyncio.run(teardown_pilot()))
    else:
        summary = asyncio.run(seed_pilot())
        print(summary.render())
        assert summary.admin_created + summary.admin_existing == 1 and \
            summary.clients_created + summary.clients_existing == len(CLIENT_DOCS) and \
            summary.technicians_created + summary.technicians_existing == len(TECHNICIAN_DATA), \
            f"El seed debe converger a {len(CLIENT_DOCS)} clientes + {len(TECHNICIAN_DATA)} técnicos + 1 admin"
        print("Verificación del admin: documento 1000000001 / AdminPiloto123 (sesión <= 4h, RF-AUTH-003)")
        print("Clientes/técnicos: documento 2000000001..05 / 3000000001..05, password PilotoCold456")
