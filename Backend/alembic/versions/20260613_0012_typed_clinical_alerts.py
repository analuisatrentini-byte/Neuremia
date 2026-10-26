"""typed clinical alerts

Revision ID: 0012_typed_clinical_alerts
Revises: 0011_composite_indexes_assessments_alerts
Create Date: 2026-06-13 00:12:00.000000
"""

from alembic import op
import sqlalchemy as sa


revision = "0012_typed_clinical_alerts"
down_revision = "0011_composite_indexes_assessments_alerts"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "clinical_alerts",
        sa.Column(
            "alert_type",
            sa.String(length=64),
            nullable=False,
            server_default="psychiatric_emergency",
        ),
    )
    op.add_column(
        "clinical_alerts",
        sa.Column(
            "escalation_target",
            sa.String(length=64),
            nullable=False,
            server_default="clinician_caregiver_now",
        ),
    )
    op.create_index(
        "ix_alerts_type_target",
        "clinical_alerts",
        ["alert_type", "escalation_target"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_alerts_type_target", table_name="clinical_alerts")
    op.drop_column("clinical_alerts", "escalation_target")
    op.drop_column("clinical_alerts", "alert_type")
