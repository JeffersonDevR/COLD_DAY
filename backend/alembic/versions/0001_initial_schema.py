"""initial schema

Revision ID: 0001
Revises:
Create Date: 2026-08-19

Esquema ACTUAL de modelos (S6 mvp-polish, RF-PILOT-001): captura TODO lo que
`create_all` + el bridge de ALTERs idempotentes construían hasta S5 — tablas,
columnas, defaults y constraints exactos de la DB dev (fuente de verdad).

Notas de diseño:
- `service_requests.user_id` NO lleva FK acá: las filas legacy huérfanas
  (user_id sin users) impiden el constraint — llega en 0002 (delta S6) tras
  limpiar los huérfanos. *service_requests
- Índices GiST sobre location (idx_*_location) preservados de la DB dev: los
  usa la búsqueda ST_DWithin del radar (RF-MATCH-001/004).
- Constraint único del pacto (uq_service_agreements_active_request) y de
  reviews.service_request_id (RF-RAT-004) como en la DB dev.
- Strings para estados (decisión design §Enums): sin tipos enum PG.
"""

from alembic import op
import sqlalchemy as sa
from geoalchemy2 import Geometry

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- Catálogo (sin cambios en mvp-polish) ---------------------------------
    op.create_table(
        "equipment_categories",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=50), nullable=False),
        sa.Column("icon", sa.String(length=50), nullable=True),
        sa.Column("technologies", sa.JSON(), nullable=True),
        sa.UniqueConstraint("name", name="equipment_categories_name_key"),
    )
    op.create_index("ix_equipment_categories_id", "equipment_categories", ["id"])

    op.create_table(
        "equipments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("category_id", sa.Integer(), sa.ForeignKey("equipment_categories.id"), nullable=False),
        sa.Column("sector", sa.String(length=50), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
    )
    op.create_index("ix_equipments_id", "equipments", ["id"])

    op.create_table(
        "service_pricings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("category_id", sa.Integer(), sa.ForeignKey("equipment_categories.id"), nullable=False),
        sa.Column("sector", sa.String(length=50), nullable=False),
        sa.Column("service_type", sa.String(length=50), nullable=False),
        sa.Column("base_price", sa.Float(), nullable=False),
        sa.Column("estimated_time_minutes", sa.Integer(), nullable=True),
    )
    op.create_index("ix_service_pricings_id", "service_pricings", ["id"])

    # --- Auth (S1): users + auth_tokens ---------------------------------------
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("full_name", sa.String(length=100), nullable=False),
        sa.Column("document", sa.String(length=20), nullable=False),
        sa.Column("phone", sa.String(length=30), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("role", sa.String(length=20), nullable=False),  # default Python-side (modelo)
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    # document: unique=True + index=True -> índice único (como create_all).
    op.create_index("ix_users_document", "users", ["document"], unique=True)
    op.create_index("ix_users_id", "users", ["id"])

    op.create_table(
        "auth_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_auth_tokens_token_hash", "auth_tokens", ["token_hash"], unique=True)
    op.create_index("ix_auth_tokens_id", "auth_tokens", ["id"])

    # --- Técnicos (S1 delta: user_id + verification_status + availability) -----
    op.create_table(
        "technicians",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("rating", sa.Float(), nullable=True),  # default Python-side (modelo)
        sa.Column("specialty", sa.String(length=100), nullable=True),
        sa.Column("location", Geometry(geometry_type="POINT", srid=4326), nullable=False),
        sa.Column("verification_status", sa.String(length=20), nullable=False, server_default="pending"),
        sa.Column("rejection_reason", sa.Text(), nullable=True),
        sa.Column("availability", sa.String(length=10), nullable=False, server_default="free"),
    )
    op.create_index("ix_technicians_id", "technicians", ["id"])
    # Index GiST espacial: lo crea GeoAlchemy2 automáticamente al crear la
    # columna Geometry (spatial_index=True) — no declararlo explícito.

    # --- Solicitudes (S1/S3 delta; FK a users llega en 0002) -------------------
    op.create_table(
        "service_requests",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), nullable=False),  # FK real en 0002
        sa.Column("equipment_id", sa.Integer(), sa.ForeignKey("equipments.id"), nullable=False),
        sa.Column("service_type", sa.String(length=50), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("location", Geometry(geometry_type="POINT", srid=4326), nullable=False),
        sa.Column("budget_offered", sa.Float(), nullable=True),
        sa.Column("status", sa.String(length=50), nullable=False),  # default Python-side (modelo)
        sa.Column("assigned_technician_id", sa.Integer(), sa.ForeignKey("technicians.id"), nullable=True),
        sa.Column("diagnosis_observations", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_service_requests_id", "service_requests", ["id"])
    # Index GiST espacial de location: geoaalchemy2 lo crea automáticamente.

    # --- Bids (S2 contract-fix: costos; FK real technician en bridge S3) --------
    op.create_table(
        "technician_bids",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("service_request_id", sa.Integer(), sa.ForeignKey("service_requests.id"), nullable=False),
        sa.Column("technician_id", sa.Integer(), sa.ForeignKey("technicians.id", name="fk_technician_bids_technician"), nullable=False),
        sa.Column("price_offered", sa.Float(), nullable=False),
        sa.Column("transport_cost", sa.Float(), nullable=False, server_default="0.0"),
        sa.Column("diagnosis_cost", sa.Float(), nullable=False, server_default="0.0"),
        sa.Column("estimated_time_minutes", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=50), nullable=True),  # modelo sin nullable=False
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_technician_bids_id", "technician_bids", ["id"])

    # --- Pacto de servicio (S3) --------------------------------------------------
    op.create_table(
        "service_agreements",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("service_request_id", sa.Integer(), sa.ForeignKey("service_requests.id"), nullable=False),
        sa.Column("technician_id", sa.Integer(), sa.ForeignKey("technicians.id"), nullable=False),
        sa.Column("labor_cost", sa.Float(), nullable=False),
        sa.Column("transport_cost", sa.Float(), nullable=False),  # sin default server (modelo)
        sa.Column("diagnosis_cost", sa.Float(), nullable=False),
        sa.Column("total", sa.Float(), nullable=False),
        sa.Column("observations", sa.Text(), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),  # default Python-side (modelo)
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
    )
    # Un único pacto activo (no rechazado) por solicitud (RF-SR-005/007).
    op.create_index(
        "uq_service_agreements_active_request",
        "service_agreements",
        ["service_request_id"],
        unique=True,
        postgresql_where=sa.text("status != 'rejected'"),
    )
    op.create_index("ix_service_agreements_id", "service_agreements", ["id"])

    # --- Reviews (S4 ratings; constraint único -> 409 RF-RAT-004) ---------------
    op.create_table(
        "reviews",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("service_request_id", sa.Integer(), sa.ForeignKey("service_requests.id"), nullable=False),
        sa.Column("client_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("technician_id", sa.Integer(), sa.ForeignKey("technicians.id"), nullable=False),
        sa.Column("punctuality", sa.Integer(), nullable=False),
        sa.Column("quality", sa.Integer(), nullable=False),
        sa.Column("professionalism", sa.Integer(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("global_score", sa.Float(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("service_request_id", name="reviews_service_request_id_key"),
    )
    op.create_index("ix_reviews_id", "reviews", ["id"])


def downgrade() -> None:
    # Orden inverso de dependencias (FK).
    op.drop_index("ix_reviews_id", table_name="reviews")
    op.drop_table("reviews")
    op.drop_index("ix_service_agreements_id", table_name="service_agreements")
    op.drop_index("uq_service_agreements_active_request", table_name="service_agreements")
    op.drop_table("service_agreements")
    op.drop_index("ix_technician_bids_id", table_name="technician_bids")
    op.drop_table("technician_bids")
    op.drop_index("ix_service_requests_id", table_name="service_requests")
    op.drop_table("service_requests")
    op.drop_index("ix_technicians_id", table_name="technicians")
    op.drop_table("technicians")
    op.drop_index("ix_auth_tokens_id", table_name="auth_tokens")
    op.drop_index("ix_auth_tokens_token_hash", table_name="auth_tokens")
    op.drop_table("auth_tokens")
    op.drop_index("ix_users_id", table_name="users")
    op.drop_index("ix_users_document", table_name="users")
    op.drop_table("users")
    op.drop_index("ix_service_pricings_id", table_name="service_pricings")
    op.drop_table("service_pricings")
    op.drop_index("ix_equipments_id", table_name="equipments")
    op.drop_table("equipments")
    op.drop_index("ix_equipment_categories_id", table_name="equipment_categories")
    op.drop_table("equipment_categories")