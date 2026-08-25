"""add selected equipment technology to service requests

Revision ID: 0004
Revises: 0003
"""

from alembic import op
import sqlalchemy as sa


revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "service_requests",
        sa.Column("technology", sa.String(length=20), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("service_requests", "technology")
