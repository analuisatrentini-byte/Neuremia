"""add users.token_epoch

Revision ID: 0007_users_token_epoch
Revises: 0006_revoked_access_tokens
Create Date: 2026-06-12

Sprint 15 / S47: a single bumpable counter per user lets us invalidate every
access token they ever held in O(1) time. The JWT carries the issuance
epoch; current_user rejects requests whose epoch is below the user's
current value.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0007_users_token_epoch"
down_revision: Union[str, None] = "0006_revoked_access_tokens"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "token_epoch",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "token_epoch")
