"""composite index on daily_check_in(patient_id, created_at)

Revision ID: 0010_checkin_patient_date_idx
Revises: 0009_encrypt_pii
Create Date: 2026-06-13

Queries that list a patient's check-ins ordered by date (the most common
read path for the clinician dashboard and retention-delete endpoint) were
doing a full table scan on `created_at` after filtering by `patient_id`.
A composite index on (patient_id, created_at DESC) lets the DB satisfy
both the WHERE and ORDER BY in a single index scan.
"""
from typing import Sequence, Union

from alembic import op


revision: str = "0010_checkin_patient_date_idx"
down_revision: Union[str, None] = "0009_encrypt_pii"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index(
        "ix_daily_checkin_patient_created",
        "daily_check_in",
        ["patient_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_daily_checkin_patient_created", table_name="daily_check_in")
