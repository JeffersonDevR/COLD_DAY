from geoalchemy2 import Geometry
from sqlalchemy import JSON, Column, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship
from app.core.database import Base


class EquipmentCategory(Base):
    """Categoría de equipo, data-driven.

    Categorías actuales: Neveras, Cuartos fríos, Aire acondicionado, Lavadoras,
    Electricidad, Electrónica, Instalación de cámaras.
    """

    __tablename__ = "equipment_categories"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), nullable=False, unique=True)
    icon = Column(String(50), nullable=True)  # nombre de icono para el cliente
    # Tecnologías aplicables al equipo, p.ej. ["conventional", "inverter"].
    # null / [] = no aplica. Data-driven: se edita en la DB sin tocar código.
    technologies = Column(JSON, nullable=True)

    equipments = relationship("Equipment", back_populates="category")


class Equipment(Base):
    """Equipo concreto, pertenece a una categoría y a un sector."""

    __tablename__ = "equipments"

    id = Column(Integer, primary_key=True, index=True)
    category_id = Column(
        Integer, ForeignKey("equipment_categories.id"), nullable=False
    )
    sector = Column(String(50), nullable=False)  # "residential" o "industrial"
    name = Column(String(100), nullable=False)
    description = Column(Text, nullable=True)

    category = relationship("EquipmentCategory", back_populates="equipments")


class ServicePricing(Base):
    """Precio base por categoría + sector + tipo de servicio.

    Luis pidió explícitamente diferenciar servicios residenciales e
    industriales por el precio y el técnico: acá vive esa diferencia.
    """

    __tablename__ = "service_pricings"

    id = Column(Integer, primary_key=True, index=True)
    category_id = Column(
        Integer, ForeignKey("equipment_categories.id"), nullable=False
    )
    sector = Column(String(50), nullable=False)  # "residential" o "industrial"
    service_type = Column(
        String(50), nullable=False
    )  # "installation", "maintenance", "repair"
    base_price = Column(Float, nullable=False)  # COP
    estimated_time_minutes = Column(Integer, nullable=True)


class ServiceRequest(Base):
    __tablename__ = "service_requests"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False)
    equipment_id = Column(Integer, ForeignKey("equipments.id"), nullable=False)
    service_type = Column(
        String(50), nullable=False
    )  # "installation", "maintenance", "repair"
    description = Column(Text, nullable=False)

    # Geolocalización PostGIS (Punto WGS 84 - Longitud, Latitud)
    location = Column(Geometry(geometry_type="POINT", srid=4326), nullable=False)

    budget_offered = Column(
        Float, nullable=True
    )  # Presupuesto inicial del cliente
    status = Column(
        String(50), default="pending"
    )  # pending, bidding, assigned, completed

    equipment = relationship("Equipment")
    bids = relationship(
        "TechnicianBid", back_populates="service_request", cascade="all, delete"
    )


class Technician(Base):
    __tablename__ = "technicians"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    rating = Column(Float, default=0.0)
    specialty = Column(String(100), nullable=True)
    location = Column(Geometry(geometry_type="POINT", srid=4326), nullable=False)


class TechnicianBid(Base):
    __tablename__ = "technician_bids"

    id = Column(Integer, primary_key=True, index=True)
    service_request_id = Column(
        Integer, ForeignKey("service_requests.id"), nullable=False
    )
    technician_id = Column(Integer, nullable=False)
    price_offered = Column(
        Float, nullable=False
    )  # Contraoferta del técnico
    estimated_time_minutes = Column(Integer, nullable=False)
    status = Column(
        String(50), default="pending"
    )  # pending, accepted, rejected

    service_request = relationship("ServiceRequest", back_populates="bids")
