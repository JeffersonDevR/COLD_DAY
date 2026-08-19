from geoalchemy2 import Geometry
from sqlalchemy import (
    JSON,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func,
    text,
)
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
    # FK real a users.id (design §Delta modelos): el dueño sale del token, nunca
    # del payload. La constraint física llega con Alembic (S6, RF-PILOT-001).
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
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
    # Máquina de estados PINNED (spec §3): requested -> bidding -> diagnosis ->
    # pact_proposed -> in_progress -> completed; terminales: cancelled/completed.
    status = Column(String(50), default="requested", nullable=False)
    # Técnico asignado al aceptar un bid (RF-SR-003, atómico: design §Máquina).
    assigned_technician_id = Column(
        Integer, ForeignKey("technicians.id"), nullable=True
    )
    # Observaciones del diagnóstico del técnico asignado (RF-SR-004).
    diagnosis_observations = Column(Text, nullable=True)
    # Historial del cliente ordenado por fecha desc (RF-SR-010).
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    equipment = relationship("Equipment")
    bids = relationship(
        "TechnicianBid", back_populates="service_request", cascade="all, delete"
    )
    agreements = relationship(
        "ServiceAgreement", back_populates="service_request", cascade="all, delete"
    )
    assigned_technician = relationship(
        "Technician", foreign_keys=[assigned_technician_id]
    )


class Technician(Base):
    __tablename__ = "technicians"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)  # backfill S1
    name = Column(String(100), nullable=False)
    rating = Column(Float, default=0.0)
    specialty = Column(String(100), nullable=True)
    location = Column(Geometry(geometry_type="POINT", srid=4326), nullable=False)
    # S1 delta (design §Delta modelos): pending/verified/rejected; pending por
    # defecto — solo técnicos verified+free aparecen en el radar (RF-TEC-005).
    verification_status = Column(
        String(20), nullable=False, default="pending"
    )  # pending, verified, rejected
    rejection_reason = Column(Text, nullable=True)
    availability = Column(String(10), nullable=False, default="free")  # free, busy


class TechnicianBid(Base):
    __tablename__ = "technician_bids"

    id = Column(Integer, primary_key=True, index=True)
    service_request_id = Column(
        Integer, ForeignKey("service_requests.id"), nullable=False
    )
    # FK real a technicians.id (design §Delta modelos). Un solo bid por
    # (request, technician) -> 409 (RF-TEC-007), validado en lifecycle.create_bid.
    technician_id = Column(Integer, ForeignKey("technicians.id"), nullable=False)
    price_offered = Column(
        Float, nullable=False
    )  # Contraoferta del técnico (informativa, no entra en el total del pacto)
    transport_cost = Column(Float, nullable=False, default=0.0)
    diagnosis_cost = Column(Float, nullable=False, default=0.0)
    estimated_time_minutes = Column(Integer, nullable=False)
    status = Column(
        String(50), default="pending"
    )  # pending, accepted, rejected
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    service_request = relationship("ServiceRequest", back_populates="bids")
    technician = relationship("Technician")


class ServiceAgreement(Base):
    """Pacto de Servicio (RF-SR-005/006/007): entidad histórica con ciclo propio.

    Desglose `labor_cost` + `transport_cost` + `diagnosis_cost` con `total` =
    suma (el price_offered del bid NO entra). Los pactos rechazados quedan como
    histórico (mercado reabre, RF-SR-007); a lo sumo UN pacto activo (no
    rechazado) por solicitud -> índice único parcial sobre service_request_id.
    """

    __tablename__ = "service_agreements"
    __table_args__ = (
        Index(
            "uq_service_agreements_active_request",
            "service_request_id",
            unique=True,
            postgresql_where=text("status != 'rejected'"),
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    service_request_id = Column(
        Integer, ForeignKey("service_requests.id"), nullable=False
    )
    technician_id = Column(Integer, ForeignKey("technicians.id"), nullable=False)
    labor_cost = Column(Float, nullable=False)
    transport_cost = Column(Float, nullable=False, default=0.0)
    diagnosis_cost = Column(Float, nullable=False, default=0.0)
    total = Column(Float, nullable=False)  # labor + transport + diagnosis
    # Observaciones del diagnóstico (RF-SR-005: el pacto las incluye).
    observations = Column(Text, nullable=True)
    status = Column(
        String(20), nullable=False, default="proposed"
    )  # proposed, accepted, rejected
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    decided_at = Column(DateTime(timezone=True), nullable=True)

    service_request = relationship("ServiceRequest", back_populates="agreements")
    technician = relationship("Technician")


class Review(Base):
    """Evaluación del cliente al técnico tras finalizar (S4 ratings, RF-RAT-001..006).

    Una sola por solicitud: `service_request_id` UNIQUE -> duplicado 409
    (RF-RAT-004). `global_score` = promedio 1 decimal de las 3 sub-dimensiones
    (RF-RAT-003); `Technician.rating` se recalcula como promedio de los
    puntajes globales (RF-RAT-005).
    """

    __tablename__ = "reviews"

    id = Column(Integer, primary_key=True, index=True)
    service_request_id = Column(
        Integer, ForeignKey("service_requests.id"), nullable=False, unique=True
    )
    client_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    technician_id = Column(Integer, ForeignKey("technicians.id"), nullable=False)
    punctuality = Column(Integer, nullable=False)  # 1-5 (RF-RAT-002)
    quality = Column(Integer, nullable=False)  # 1-5 (RF-RAT-002)
    professionalism = Column(Integer, nullable=False)  # 1-5 (RF-RAT-002)
    # Comentario opcional <= 1000 caracteres (RF-RAT-002); validado en schema.
    comment = Column(Text, nullable=True)
    global_score = Column(Float, nullable=False)  # promedio 1 decimal
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
