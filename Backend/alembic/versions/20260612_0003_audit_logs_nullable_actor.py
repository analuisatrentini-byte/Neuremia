"""make audit_logs.actor_user_id nullable

Revision ID: 0003_audit_logs_nullable_actor
Revises: 0002_refresh_tokens
Create Date: 2026-06-12

DELETE /me used to drop AuditLog rows so the user FK could be removed; this
violated LGPD recommendations for retaining access logs for breach response.
Making the column nullable lets us null out the FK reference instead, keeping
the audit trail intact.

We avoid `batch_alter_table` on Postgres because it triggers a full table
recreate. Only SQLite needs the batch dance to support ALTER COLUMN.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0003_audit_logs_nullable_actor"
down_revision: Union[str, None] = "0002_refresh_tokens"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _is_sqlite() -> bool:
    return op.get_bind().dialect.name == "sqlite"


def upgrade() -> None:
    if _is_sqlite():
        with op.batch_alter_table("audit_logs") as batch_op:
            batch_op.alter_column(
                "actor_user_id",
                existing_type=sa.Integer(),
                nullable=True,
            )
    else:
        op.alter_column(
            "audit_logs",
            "actor_user_id",
            existing_type=sa.Integer(),
            nullable=True,
        )


def downgrade() -> None:
    if _is_sqlite():
        with op.batch_alter_table("audit_logs") as batch_op:
            batch_op.alter_column(
                "actor_user_id",
                existing_type=sa.Integer(),
                nullable=False,
            )
    else:
        op.alter_column(
            "audit_logs",
            "actor_user_id",
            existing_type=sa.Integer(),
            nullable=False,
        )
