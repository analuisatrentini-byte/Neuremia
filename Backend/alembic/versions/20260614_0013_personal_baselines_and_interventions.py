"""personal baselines and intervention log

Introduces two tables that back the personalized-insight loop:

* ``user_baselines`` — one rolling 60-day baseline row per (patient, metric).
  Recomputed synchronously after each check-in. Enables "your mood is 1.5
  std below *your* normal" instead of population thresholds.

* ``intervention_logs`` — records that a patient used (or committed to) an
  intervention, with the baseline snapshot at trigger time. Outcome deltas
  are backfilled asynchronously once enough post-trigger check-ins arrive.

Revision ID: 0013_personal_baselines_and_interventions
Revises: 0012_typed_clinical_alerts
Create Date: 2026-06-14 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa


revision = "0013_personal_baselines_and_interventions"
down_revision = "0012_typed_clinical_alerts"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_baselines",
        sa.Column("id", sa.Integer, primary_key=True, index=True),
        sa.Column(
            "patient_id",
            sa.Integer,
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("metric", sa.String(length=32), nullable=False),
        sa.Column("window_days", sa.Integer, nullable=False, server_default="60"),
        sa.Column("sample_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("mean_value", sa.Float, nullable=False, server_default="0"),
        sa.Column("stdev_value", sa.Float, nullable=False, server_default="0"),
        sa.Column("current_value", sa.Float, nullable=False, server_default="0"),
        sa.Column(
            "computed_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.UniqueConstraint("patient_id", "metric", name="uq_user_baseline_metric"),
    )

    op.create_table(
        "intervention_logs",
        sa.Column("id", sa.Integer, primary_key=True, index=True),
        sa.Column(
            "patient_id",
            sa.Integer,
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("intervention_type", sa.String(length=64), nullable=False),
        sa.Column(
            "trigger_source",
            sa.String(length=32),
            nullable=False,
            server_default="user_manual",
        ),
        sa.Column(
            "triggered_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("baseline_snapshot_json", sa.Text, nullable=False, server_default="{}"),
        sa.Column("notes_encrypted", sa.Text, nullable=False, server_default=""),
        sa.Column("outcome_computed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("outcome_delta_json", sa.Text, nullable=True),
    )
    op.create_index(
        "ix_intervention_logs_patient_created",
        "intervention_logs",
        ["patient_id", "triggered_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_intervention_logs_patient_created",
        table_name="intervention_logs",
    )
    op.drop_table("intervention_logs")
    op.drop_table("user_baselines")
