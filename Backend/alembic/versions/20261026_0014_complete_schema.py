"""Add missing authentication, expiry, and soft-delete schema."""
from alembic import op
import sqlalchemy as sa

revision = "0014_complete_schema"
down_revision = "0013_personal_baselines_and_interventions"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("totp_secret_enc", sa.String(512), nullable=True))
    op.add_column("users", sa.Column("totp_enabled", sa.Boolean(), nullable=False, server_default=sa.false()))
    for table in ("clinical_reports", "scale_assessments"):
        op.add_column(table, sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    for table in ("clinical_reports", "scale_assessments", "clinical_alerts", "daily_checkins"):
        op.create_index(f"ix_{table}_deleted_at", table, ["deleted_at"])
    op.create_index("ix_assessments_patient_deleted", "scale_assessments", ["patient_id", "deleted_at"])
    op.add_column("clinician_patient_invites", sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index("ix_clinician_patient_invites_expires_at", "clinician_patient_invites", ["expires_at"])
    op.create_table("risk_cache",
        sa.Column("patient_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("risk_score", sa.Integer(), nullable=False),
        sa.Column("risk_level", sa.String(32), nullable=False),
        sa.Column("computed_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_risk_cache_patient_id", "risk_cache", ["patient_id"])
    op.create_table("totp_pending_sessions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("session_hash", sa.String(128), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
    )
    for column in ("id", "user_id", "session_hash", "expires_at"):
        op.create_index(f"ix_totp_pending_sessions_{column}", "totp_pending_sessions", [column], unique=column == "session_hash")


def downgrade():
    op.drop_table("totp_pending_sessions")
    op.drop_table("risk_cache")
    op.drop_index("ix_clinician_patient_invites_expires_at", table_name="clinician_patient_invites")
    op.drop_column("clinician_patient_invites", "expires_at")
    op.drop_index("ix_assessments_patient_deleted", table_name="scale_assessments")
    for table in ("clinical_reports", "scale_assessments", "clinical_alerts", "daily_checkins"):
        op.drop_index(f"ix_{table}_deleted_at", table_name=table)
    for table in ("clinical_reports", "scale_assessments"):
        op.drop_column(table, "deleted_at")
    op.drop_column("users", "totp_enabled")
    op.drop_column("users", "totp_secret_enc")
