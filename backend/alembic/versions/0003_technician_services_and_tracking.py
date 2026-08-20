"""technician services and tracking

Revision ID: 0003
Revises: 0002
Create Date: 2026-08-19

"""
from alembic import op
import sqlalchemy as sa
from geoalchemy2 import Geometry

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

def upgrade() -> None:
    # Modify service_requests
    op.alter_column('service_requests', 'equipment_id', existing_type=sa.Integer(), nullable=True)
    op.add_column('service_requests', sa.Column('category_hint', sa.String(), nullable=True))
    
    # Create technician_services
    op.create_table(
        'technician_services',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('technician_id', sa.Integer(), sa.ForeignKey('technicians.id', ondelete='CASCADE'), nullable=False),
        sa.Column('category_id', sa.Integer(), sa.ForeignKey('equipment_categories.id', ondelete='CASCADE'), nullable=False),
        sa.Column('service_types', sa.JSON(), nullable=False, server_default='["repair"]'),
        sa.Column('sector', sa.String(), nullable=False, server_default='both'),
        sa.Column('active', sa.Boolean(), nullable=False, server_default='true'),
        sa.UniqueConstraint('technician_id', 'category_id', name='uq_tech_category')
    )
    
    # Create location_updates
    op.create_table(
        'location_updates',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('service_request_id', sa.Integer(), sa.ForeignKey('service_requests.id', ondelete='CASCADE'), nullable=False),
        sa.Column('technician_id', sa.Integer(), sa.ForeignKey('technicians.id', ondelete='CASCADE'), nullable=False),
        sa.Column('location', Geometry(geometry_type="POINT", srid=4326), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text('now()')),
    )

def downgrade() -> None:
    op.drop_table('location_updates')
    op.drop_table('technician_services')
    op.drop_column('service_requests', 'category_hint')
    op.alter_column('service_requests', 'equipment_id', existing_type=sa.Integer(), nullable=False)
