from datetime import datetime
from enum import Enum

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class UserRole(str, Enum):
    patient = "patient"
    clinician = "clinician"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(32))
    # Sprint B / LGPD: armazenado encriptado (Fernet). 512 chars cobrem nomes
    # longos após Fernet (ciphertext ~140 bytes pra strings curtas).
    full_name: Mapped[str] = mapped_column(String(512))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    # Incremented every time the user wants every existing JWT killed:
    # password reset, admin-driven session revocation, account compromise
    # response (Sprint 15 / S47). Any access token presenting an `epoch`
    # claim lower than this value is rejected by current_user before any
    # business logic runs.
    token_epoch: Mapped[int] = mapped_column(
        Integer, default=0, server_default="0", nullable=False
    )
    # Sprint B: bloqueio progressivo contra credential stuffing. failed count
    # incrementa em login falho, zera em sucesso. Quando atinge threshold, o
    # endpoint /auth/login seta locked_until = now + backoff.
    failed_login_count: Mapped[int] = mapped_column(
        Integer, default=0, server_default="0", nullable=False
    )
    locked_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    # passive_deletes=True lets the DB-level ON DELETE CASCADE handle the
    # cleanup. Without it SQLAlchemy's unit-of-work tries to SET NULL the
    # patient_id on children (which is NOT NULL → IntegrityError) before
    # the parent DELETE has a chance to cascade (Sprint 15 / D4).
    checkins: Mapped[list["DailyCheckIn"]] = relationship(
        back_populates="patient", passive_deletes=True
    )
    assessments: Mapped[list["ScaleAssessment"]] = relationship(
        back_populates="patient", passive_deletes=True
    )


class ClinicianPatientLink(Base):
    __tablename__ = "clinician_patient_links"
    __table_args__ = (UniqueConstraint("clinician_id", "patient_id", name="uq_clinician_patient"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    clinician_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class InviteStatus(str, Enum):
    pending = "pending"
    accepted = "accepted"
    revoked = "revoked"


class ClinicianPatientInvite(Base):
    """Clinician requests access to a patient's record. The link is created
    only after the patient explicitly accepts."""

    __tablename__ = "clinician_patient_invites"
    __table_args__ = (
        UniqueConstraint(
            "clinician_id",
            "patient_id",
            "status",
            name="uq_clinician_patient_invite_status",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    clinician_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    status: Mapped[str] = mapped_column(String(16), default=InviteStatus.pending.value)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class CaregiverContact(Base):
    __tablename__ = "caregiver_contacts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(255))
    # Sprint B / LGPD: encriptado (Fernet). Largura 512 acomoda email/telefone
    # cifrados; descriptografia acontece só no momento de envio SMTP/push.
    contact: Mapped[str] = mapped_column(String(512))
    relationship: Mapped[str] = mapped_column(String(128), default="")
    share_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class DailyCheckIn(Base):
    __tablename__ = "daily_checkins"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    mood: Mapped[float] = mapped_column(Float)
    anxiety: Mapped[float] = mapped_column(Float)
    energy: Mapped[float] = mapped_column(Float)
    irritability: Mapped[float] = mapped_column(Float)
    sleep_hours: Mapped[float] = mapped_column(Float)
    appetite: Mapped[float] = mapped_column(Float)
    libido: Mapped[float] = mapped_column(Float)
    medication_taken: Mapped[bool] = mapped_column(Boolean)
    side_effects: Mapped[str] = mapped_column(Text, default="")
    automatic_thoughts: Mapped[str] = mapped_column(Text, default="")
    suicidal_ideation: Mapped[bool] = mapped_column(Boolean, default=False)
    journal_entry: Mapped[str] = mapped_column(Text, default="")

    patient: Mapped[User] = relationship(back_populates="checkins")


class ScaleAssessment(Base):
    __tablename__ = "scale_assessments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    scale_name: Mapped[str] = mapped_column(String(32))
    answers_json: Mapped[str] = mapped_column(Text)
    score: Mapped[int] = mapped_column(Integer)
    interpretation: Mapped[str] = mapped_column(String(255))

    patient: Mapped[User] = relationship(back_populates="assessments")


class ClinicalAlert(Base):
    __tablename__ = "clinical_alerts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    level: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(String(255))
    message: Mapped[str] = mapped_column(Text)
    acknowledged: Mapped[bool] = mapped_column(Boolean, default=False)


class ClinicalReport(Base):
    __tablename__ = "clinical_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    risk_level: Mapped[str] = mapped_column(String(32))
    summary: Mapped[str] = mapped_column(Text)


class DeviceToken(Base):
    __tablename__ = "device_tokens"
    __table_args__ = (UniqueConstraint("user_id", "token", name="uq_user_device_token"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token: Mapped[str] = mapped_column(String(512), index=True)
    platform: Mapped[str] = mapped_column(String(32), default="ios")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class NotificationLog(Base):
    __tablename__ = "notification_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    recipient: Mapped[str] = mapped_column(String(255))
    channel: Mapped[str] = mapped_column(String(32))
    event_type: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(32))
    detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class RevokedAccessToken(Base):
    """Blacklist of access-token JTIs that should be rejected before they
    expire naturally. Logout adds the current bearer's jti so a stolen access
    token can be killed inside its 30-minute TTL window (Sprint 14 / S34)."""

    __tablename__ = "revoked_access_tokens"

    jti: Mapped[str] = mapped_column(String(64), primary_key=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    revoked_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class PasswordResetToken(Base):
    """Short-lived single-use credential for the forgot-password flow. Only
    the SHA-256 hash of the raw code is stored; the raw value is sent over
    e-mail. Tokens expire in 30 minutes and are marked used the first time
    they're consumed (Sprint 13 / S9)."""

    __tablename__ = "password_reset_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class RefreshToken(Base):
    """Long-lived refresh credential. Only the SHA-256 hash is stored — the
    raw token never persists in the DB. Rotated on every /auth/refresh call
    so a stolen refresh token can be revoked without forcing all users out.

    ON DELETE CASCADE on user_id (Sprint 11) keeps the table consistent with
    account deletion. `expires_at` is indexed to keep the admin purge
    endpoint (Sprint 10) cheap as the table grows."""

    __tablename__ = "refresh_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class ConsentPurpose(str, Enum):
    """Sprint B / LGPD Art. 7 II + Art. 9: consentimento separado por
    finalidade. O paciente pode revogar uma sem afetar as outras."""
    clinical_data_storage = "clinical_data_storage"
    clinician_sharing = "clinician_sharing"
    caregiver_sharing = "caregiver_sharing"
    research_anonymized = "research_anonymized"


class Consent(Base):
    """Registro auditável de consentimento explícito por finalidade.
    Outorga e revogação geram entradas distintas — histórico é mantido para
    fins de auditoria regulatória (LGPD/HIPAA)."""
    __tablename__ = "consents"
    __table_args__ = (
        UniqueConstraint("user_id", "purpose", name="uq_consents_user_purpose"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    purpose: Mapped[str] = mapped_column(String(64))
    granted_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # Versão textual da política aceita no momento do consentimento — permite
    # auditar EXATAMENTE qual texto o usuário viu (LGPD Art. 8 §6º).
    policy_version: Mapped[str] = mapped_column(String(32), default="")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    # Nullable so DELETE /me can null out the FK without losing the audit
    # trail. LGPD allows retention of access logs for breach response.
    actor_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    action: Mapped[str] = mapped_column(String(255))
    resource_type: Mapped[str] = mapped_column(String(128))
    resource_id: Mapped[str] = mapped_column(String(128))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
