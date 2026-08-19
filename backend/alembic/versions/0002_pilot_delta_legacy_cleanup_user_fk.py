"""pilot delta: cleanup legacy orphans + real user FK

Revision ID: 0002
Revises: 0001
Create Date: 2026-08-19

Delta S6 sobre la DB dev existente (RF-PILOT-001, design §Migraciones):
los datos legacy (pre-auth) tienen solicitudes huérfanas cuya `user_id` no
existe en `users` (la FK real se había diferido a S6 porque `create_all` no
altera tablas existentes). Esta migración:

1. Elimina las solicitudes huérfanas (user_id NULL o sin usuario) y sus bids
   dependientes — no tienen dueño y su estado `requested` las deja fuera del
   piloto (RF-SR-001: el dueño siempre sale del token).
2. Agrega la FK real `service_requests.user_id -> users.id` (RF-SR-001,
   aislamiento por propiedad). Con esto el bridge de ALTERs del conftest
   queda solo como helper; producción usa migraciones.

Cancelación (downgrade): quita solo la FK. Los huérfanos borrados NO se
restauran (pérdida aceptada y documentada: eran filas sin dueño).
"""

from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1) Limpieza de datos legacy: ids huérfanos (user_id NULL o sin users).
    op.execute(
        """
        DELETE FROM technician_bids
        WHERE service_request_id IN (
            SELECT id FROM service_requests
            WHERE user_id IS NULL
               OR NOT EXISTS (SELECT 1 FROM users u WHERE u.id = service_requests.user_id)
        )
        """
    )
    op.execute(
        """
        DELETE FROM service_requests
        WHERE user_id IS NULL
           OR NOT EXISTS (SELECT 1 FROM users u WHERE u.id = service_requests.user_id)
        """
    )

    # 2) FK real del dueño de la solicitud (RF-SR-001/012).
    op.create_foreign_key(
        "fk_service_requests_user",
        "service_requests",
        "users",
        ["user_id"],
        ["id"],
    )


def downgrade() -> None:
    op.drop_constraint("fk_service_requests_user", "service_requests", type_="foreignkey")