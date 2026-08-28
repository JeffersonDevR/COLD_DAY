#!/usr/bin/env python3
"""Seed de solicitudes de prueba y verificación de técnicos para probar el Radar y el Mapa.

Uso:
    cd backend && python scripts/seed_demo_requests.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select, update
from app.core.database import AsyncSessionLocal
from app.models.service import Equipment, ServiceRequest, Technician
from app.models.user import User


DEMO_REQUESTS = [
    {
        "client_doc": "2000000001",
        "service_type": "repair",
        "category_hint": "Neveras",
        "description": "Nevera no enfría en la parte inferior y bota agua al suelo.",
        "latitude": 7.8960,
        "longitude": -72.5060,
        "budget_offered": 80000.0,
        "status": "requested",
    },
    {
        "client_doc": "2000000002",
        "service_type": "maintenance",
        "category_hint": "Aire acondicionado",
        "description": "Mantenimiento preventivo de aire acondicionado Split en sala principal.",
        "latitude": 7.9010,
        "longitude": -72.5120,
        "budget_offered": 95000.0,
        "status": "requested",
    },
    {
        "client_doc": "2000000003",
        "service_type": "installation",
        "category_hint": "Aire acondicionado",
        "description": "Instalación de unidad Split inverter de 12000 BTU.",
        "latitude": 7.8890,
        "longitude": -72.5020,
        "budget_offered": 150000.0,
        "status": "bidding",
    },
    {
        "client_doc": "2000000004",
        "service_type": "repair",
        "category_hint": "Lavadoras",
        "description": "Lavadora industrial no centrifuga y genera ruido metálico.",
        "latitude": 7.8920,
        "longitude": -72.5160,
        "budget_offered": 110000.0,
        "status": "requested",
    },
]


async def seed_demo_requests():
    async with AsyncSessionLocal() as session:
        # 1. Verificar técnicos del seed para que tengan acceso al radar
        tech_update = await session.execute(
            update(Technician)
            .where(Technician.verification_status == "pending")
            .values(verification_status="verified", availability="free")
        )
        print(f"-> Técnicos verificados: {tech_update.rowcount}")

        # 2. Obtener usuarios clientes y equipos disponibles
        created_count = 0
        for req_data in DEMO_REQUESTS:
            user = (
                await session.execute(
                    select(User).where(User.document == req_data["client_doc"])
                )
            ).scalar_one_or_none()

            if not user:
                continue

            equipment = (
                await session.execute(
                    select(Equipment).limit(1)
                )
            ).scalar_one_or_none()

            # Evitar duplicar solicitudes si ya existen con la misma descripción
            existing = (
                await session.execute(
                    select(ServiceRequest).where(
                        ServiceRequest.user_id == user.id,
                        ServiceRequest.description == req_data["description"],
                    )
                )
            ).scalar_one_or_none()

            if existing:
                continue

            point_wkt = f"POINT({req_data['longitude']} {req_data['latitude']})"
            sr = ServiceRequest(
                user_id=user.id,
                equipment_id=equipment.id if equipment else None,
                category_hint=req_data["category_hint"],
                service_type=req_data["service_type"],
                description=req_data["description"],
                location=point_wkt,
                budget_offered=req_data["budget_offered"],
                status=req_data["status"],
            )
            session.add(sr)
            created_count += 1

        await session.commit()
        print(f"-> Solicitudes de prueba creadas: {created_count}")
        print("Listo para probar el mapa y radar en Flutter con datos reales.")


if __name__ == "__main__":
    asyncio.run(seed_demo_requests())
