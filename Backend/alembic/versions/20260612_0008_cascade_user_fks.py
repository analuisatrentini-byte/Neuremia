"""apply ON DELETE CASCADE / SET NULL to user-bound foreign keys

Revision ID: 0008_cascade_user_fks
Revises: 0007_users_token_epoch
Create Date: 2026-06-12

Sprint 15 / D4: every per-user table now cascades on DELETE so removing a
user row cleans up their data atomically at the DB layer. Audit logs use
SET NULL to preserve the forensic trail (Sprint 10).

Tables touched:
- clinician_patient_links (clinician_id + patient_id)
- caregiver_contacts (patient_id)
- daily_checkins (patient_id)
- scale_assessments (patient_id)
- clinical_alerts (patient_id)
- clinical_reports (patient_id)
- device_tokens (user_id)
- notification_logs (patient_id)
- clinician_patient_invites (clinician_id + patient_id)
- audit_logs (actor_user_id → SET NULL)
"""
from typing import Sequence, Union

from alembic import op


revision: str = "0008_cascade_user_fks"
down_revision: Union[str, None] = "0007_users_token_epoch"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


CASCADE_TABLES = [
    ("clinician_patient_links", ["clinician_id", "patient_id"]),
    ("caregiver_contacts", ["patient_id"]),
    ("daily_checkins", ["patient_id"]),
    ("scale_assessments", ["patient_id"]),
    ("clinical_alerts", ["patient_id"]),
    ("clinical_reports", ["patient_id"]),
    ("device_tokens", ["user_id"]),
    ("notification_logs", ["patient_id"]),
    ("clinician_patient_invites", ["clinician_id", "patient_id"]),
]


def _is_sqlite() -> bool:
    return op.get_bind().dialect.name == "sqlite"


def _recreate_fk(table: str, column: str, ondelete: str) -> None:
    constraint_name = f"fk_{table}_{column}_users"
    if _is_sqlite():
        with op.batch_alter_table(table) as batch_op:
            batch_op.drop_constraint(None, type_="foreignkey")
            batch_op.create_foreign_key(
                constraint_name,
                "users",
                [column],
                ["id"],
                ondelete=ondelete,
            )
    else:
        op.drop_constraint(f"{table}_{column}_fkey", table, type_="foreignkey")
        op.create_foreign_key(
            constraint_name,
            table,
            "users",
            [column],
            ["id"],
            ondelete=ondelete,
        )


def upgrade() -> None:
    for table, columns in CASCADE_TABLES:
        for column in columns:
            _recreate_fk(table, column, ondelete="CASCADE")

    _recreate_fk("audit_logs", "actor_user_id", ondelete="SET NULL")


def downgrade() -> None:
    for table, columns in CASCADE_TABLES:
        for column in columns:
            _recreate_fk(table, column, ondelete="NO ACTION")
    _recreate_fk("audit_logs", "actor_user_id", ondelete="NO ACTION")
