"""composite indexes on scale_assessments and clinical_alerts

Revision ID: 0011_composite_indexes_assessments_alerts
Revises: 0010_checkin_patient_date_idx
Create Date: 2026-06-13

Adds composite indexes to speed up the common query patterns:
- scale_assessments filtered by patient_id ordered by created_at
- clinical_alerts filtered by patient_id + deleted_at (soft-delete read path)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0011_composite_indexes_assessments_alerts"
down_revision: Union[str, None] = "0010_checkin_patient_date_idx"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    for table in ("clinical_alerts", "daily_checkins"):
        op.add_column(table, sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index(
        "ix_assessments_patient_created",
        "scale_assessments",
        ["patient_id", "created_at"],
    )
    op.create_index(
        "ix_alerts_patient_created",
        "clinical_alerts",
        ["patient_id", "created_at"],
    )
    op.create_index(
        "ix_alerts_patient_deleted",
        "clinical_alerts",
        ["patient_id", "deleted_at"],
    )
    op.create_index(
        "ix_checkins_patient_deleted",
        "daily_checkins",
        ["patient_id", "deleted_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_checkins_patient_deleted", table_name="daily_checkins")
    op.drop_index("ix_alerts_patient_deleted", table_name="clinical_alerts")
    op.drop_index("ix_alerts_patient_created", table_name="clinical_alerts")
    op.drop_index("ix_assessments_patient_created", table_name="scale_assessments")
    for table in ("clinical_alerts", "daily_checkins"):
        op.drop_column(table, "deleted_at")
