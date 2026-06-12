"""baseline schema (users, links, caregivers, checkins, assessments, alerts,
reports, device tokens, notification logs, audit logs, clinician invites)

Revision ID: 0001_baseline
Revises:
Create Date: 2026-06-11

This snapshot mirrors the model state as of the Sprint 1+2+3 work. It must run
against a fresh database. To bootstrap an existing dev database that was
populated by the legacy Base.metadata.create_all() path, stamp the database
without applying SQL:

    alembic stamp head
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0001_baseline"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("role", sa.String(length=32), nullable=False),
        sa.Column("full_name", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)
    op.create_index("ix_users_id", "users", ["id"], unique=False)

    op.create_table(
        "clinician_patient_links",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("clinician_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("clinician_id", "patient_id", name="uq_clinician_patient"),
    )
    op.create_index("ix_clinician_patient_links_clinician_id", "clinician_patient_links", ["clinician_id"])
    op.create_index("ix_clinician_patient_links_patient_id", "clinician_patient_links", ["patient_id"])

    op.create_table(
        "clinician_patient_invites",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("clinician_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("decided_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint(
            "clinician_id", "patient_id", "status", name="uq_clinician_patient_invite_status"
        ),
    )
    op.create_index(
        "ix_clinician_patient_invites_clinician_id", "clinician_patient_invites", ["clinician_id"]
    )
    op.create_index(
        "ix_clinician_patient_invites_patient_id", "clinician_patient_invites", ["patient_id"]
    )

    op.create_table(
        "caregiver_contacts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("contact", sa.String(length=255), nullable=False),
        sa.Column("relationship", sa.String(length=128), nullable=False),
        sa.Column("share_enabled", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_caregiver_contacts_patient_id", "caregiver_contacts", ["patient_id"])

    op.create_table(
        "daily_checkins",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("mood", sa.Float(), nullable=False),
        sa.Column("anxiety", sa.Float(), nullable=False),
        sa.Column("energy", sa.Float(), nullable=False),
        sa.Column("irritability", sa.Float(), nullable=False),
        sa.Column("sleep_hours", sa.Float(), nullable=False),
        sa.Column("appetite", sa.Float(), nullable=False),
        sa.Column("libido", sa.Float(), nullable=False),
        sa.Column("medication_taken", sa.Boolean(), nullable=False),
        sa.Column("side_effects", sa.Text(), nullable=False),
        sa.Column("automatic_thoughts", sa.Text(), nullable=False),
        sa.Column("suicidal_ideation", sa.Boolean(), nullable=False),
        sa.Column("journal_entry", sa.Text(), nullable=False),
    )
    op.create_index("ix_daily_checkins_patient_id", "daily_checkins", ["patient_id"])
    # Hot path: clinician dashboards order by created_at desc per patient.
    op.create_index(
        "ix_daily_checkins_patient_created", "daily_checkins", ["patient_id", "created_at"]
    )

    op.create_table(
        "scale_assessments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("scale_name", sa.String(length=32), nullable=False),
        sa.Column("answers_json", sa.Text(), nullable=False),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column("interpretation", sa.String(length=255), nullable=False),
    )
    op.create_index("ix_scale_assessments_patient_id", "scale_assessments", ["patient_id"])
    op.create_index(
        "ix_scale_assessments_patient_created", "scale_assessments", ["patient_id", "created_at"]
    )

    op.create_table(
        "clinical_alerts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("level", sa.String(length=32), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("acknowledged", sa.Boolean(), nullable=False),
    )
    op.create_index("ix_clinical_alerts_patient_id", "clinical_alerts", ["patient_id"])

    op.create_table(
        "clinical_reports",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("risk_level", sa.String(length=32), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
    )
    op.create_index("ix_clinical_reports_patient_id", "clinical_reports", ["patient_id"])

    op.create_table(
        "device_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token", sa.String(length=512), nullable=False),
        sa.Column("platform", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("user_id", "token", name="uq_user_device_token"),
    )
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])
    op.create_index("ix_device_tokens_token", "device_tokens", ["token"])

    op.create_table(
        "notification_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("recipient", sa.String(length=255), nullable=False),
        sa.Column("channel", sa.String(length=32), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("detail", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_notification_logs_patient_id", "notification_logs", ["patient_id"])

    op.create_table(
        "audit_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("action", sa.String(length=255), nullable=False),
        sa.Column("resource_type", sa.String(length=128), nullable=False),
        sa.Column("resource_id", sa.String(length=128), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_audit_logs_actor_user_id", "audit_logs", ["actor_user_id"])


def downgrade() -> None:
    for name in (
        "audit_logs",
        "notification_logs",
        "device_tokens",
        "clinical_reports",
        "clinical_alerts",
        "scale_assessments",
        "daily_checkins",
        "caregiver_contacts",
        "clinician_patient_invites",
        "clinician_patient_links",
        "users",
    ):
        op.drop_table(name)
