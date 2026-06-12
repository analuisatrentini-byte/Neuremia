"""encrypt users.full_name and caregiver_contacts.contact + add failed_login_count

Revision ID: 0009_encrypt_pii
Revises: 0008_cascade_user_fks
Create Date: 2026-06-12

Sprint B / LGPD:
- Encripta `users.full_name` e `caregiver_contacts.contact` at rest via Fernet
  (mesmo cipher de side_effects/journal_entry/automatic_thoughts). Dump de
  DB deixa de expor pacientes nominalmente. Backfill encripta valores
  existentes; ALTER COLUMN aumenta capacidade (Fernet ciphertext de string
  curta ~140 bytes; subimos pra 512).
- Adiciona `users.failed_login_count` e `users.locked_until` para bloqueio
  progressivo contra credential stuffing.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0009_encrypt_pii"
down_revision: Union[str, None] = "0008_cascade_user_fks"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1) Aumentar capacidade pra acomodar ciphertext Fernet.
    with op.batch_alter_table("users") as batch_op:
        batch_op.alter_column(
            "full_name",
            existing_type=sa.String(length=255),
            type_=sa.String(length=512),
            existing_nullable=False,
        )
    with op.batch_alter_table("caregiver_contacts") as batch_op:
        batch_op.alter_column(
            "contact",
            existing_type=sa.String(length=255),
            type_=sa.String(length=512),
            existing_nullable=False,
        )

    # 2) Backfill: encripta valores plaintext existentes. Importa o cipher
    #    lazily para evitar circular imports na geração de migration.
    from app.security import encrypt_field

    bind = op.get_bind()
    users_meta = sa.MetaData()
    users = sa.Table("users", users_meta, autoload_with=bind)
    caregivers = sa.Table("caregiver_contacts", users_meta, autoload_with=bind)

    for row in bind.execute(sa.select(users.c.id, users.c.full_name)).fetchall():
        ciphertext = encrypt_field(row.full_name or "")
        bind.execute(
            users.update().where(users.c.id == row.id).values(full_name=ciphertext)
        )

    for row in bind.execute(sa.select(caregivers.c.id, caregivers.c.contact)).fetchall():
        ciphertext = encrypt_field(row.contact or "")
        bind.execute(
            caregivers.update().where(caregivers.c.id == row.id).values(contact=ciphertext)
        )

    # 3) Coluna para bloqueio progressivo de login.
    op.add_column(
        "users",
        sa.Column(
            "failed_login_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "users",
        sa.Column("locked_until", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "locked_until")
    op.drop_column("users", "failed_login_count")
    # Não decriptamos no downgrade (chave pode não estar disponível). Apenas
    # restaura o tipo. Se você precisa do plaintext de volta, importe um
    # backup pré-migration.
    with op.batch_alter_table("caregiver_contacts") as batch_op:
        batch_op.alter_column(
            "contact",
            existing_type=sa.String(length=512),
            type_=sa.String(length=255),
            existing_nullable=False,
        )
    with op.batch_alter_table("users") as batch_op:
        batch_op.alter_column(
            "full_name",
            existing_type=sa.String(length=512),
            type_=sa.String(length=255),
            existing_nullable=False,
        )
