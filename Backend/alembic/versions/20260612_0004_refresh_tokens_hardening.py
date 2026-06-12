"""harden refresh_tokens lifecycle

Revision ID: 0004_refresh_tokens_hardening
Revises: 0003_audit_logs_nullable_actor
Create Date: 2026-06-12

D19: add an index on `expires_at` so the admin purge endpoint (introduced in
Sprint 10) can run efficiently as the table grows.

D20: replace the user_id foreign key with ON DELETE CASCADE so deleting a
user cleanly removes their refresh tokens without needing an extra pass in
the application layer.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0004_refresh_tokens_hardening"
down_revision: Union[str, None] = "0003_audit_logs_nullable_actor"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _is_sqlite() -> bool:
    return op.get_bind().dialect.name == "sqlite"


def upgrade() -> None:
    op.create_index(
        "ix_refresh_tokens_expires_at",
        "refresh_tokens",
        ["expires_at"],
    )

    if _is_sqlite():
        # SQLite cannot ALTER a FK constraint in place; batch_alter_table
        # recreates the table, applying the new ON DELETE CASCADE rule.
        with op.batch_alter_table("refresh_tokens") as batch_op:
            batch_op.drop_constraint(None, type_="foreignkey")
            batch_op.create_foreign_key(
                "fk_refresh_tokens_user_id_users",
                "users",
                ["user_id"],
                ["id"],
                ondelete="CASCADE",
            )
    else:
        # Postgres / others: drop + recreate the FK in two steps.
        op.drop_constraint(
            "refresh_tokens_user_id_fkey",
            "refresh_tokens",
            type_="foreignkey",
        )
        op.create_foreign_key(
            "fk_refresh_tokens_user_id_users",
            "refresh_tokens",
            "users",
            ["user_id"],
            ["id"],
            ondelete="CASCADE",
        )


def downgrade() -> None:
    if _is_sqlite():
        with op.batch_alter_table("refresh_tokens") as batch_op:
            batch_op.drop_constraint(
                "fk_refresh_tokens_user_id_users",
                type_="foreignkey",
            )
            batch_op.create_foreign_key(
                None,
                "users",
                ["user_id"],
                ["id"],
            )
    else:
        op.drop_constraint(
            "fk_refresh_tokens_user_id_users",
            "refresh_tokens",
            type_="foreignkey",
        )
        op.create_foreign_key(
            "refresh_tokens_user_id_fkey",
            "refresh_tokens",
            "users",
            ["user_id"],
            ["id"],
        )

    op.drop_index("ix_refresh_tokens_expires_at", table_name="refresh_tokens")
