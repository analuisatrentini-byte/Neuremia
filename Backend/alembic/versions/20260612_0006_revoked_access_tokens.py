"""add revoked_access_tokens

Revision ID: 0006_revoked_access_tokens
Revises: 0005_password_reset_tokens
Create Date: 2026-06-12

Sprint 14 / S34: allow explicit revocation of access JWTs by jti so the
backend can kill a token before its 30-minute TTL elapses.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0006_revoked_access_tokens"
down_revision: Union[str, None] = "0005_password_reset_tokens"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "revoked_access_tokens",
        sa.Column("jti", sa.String(length=64), primary_key=True),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=False),
    )
    op.create_index(
        "ix_revoked_access_tokens_expires_at",
        "revoked_access_tokens",
        ["expires_at"],
    )


def downgrade() -> None:
    op.drop_table("revoked_access_tokens")
