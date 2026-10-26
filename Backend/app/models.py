from datetime import datetime, timezone
from enum import Enum

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class UserRole(str, Enum):
    patient = "patient"
    clinician = "clinician"


class AlertType(str, Enum):
    psychiatric_emergency = "psychiatric_emergency"
    clinical_watch = "clinical_watch"
    self_signal = "self_signal"


class EscalationTarget(str, Enum):
    clinician_caregiver_now = "clinician_caregiver_now"
    clinician_digest = "clinician_digest"
    patient_only = "patient_only"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(32))
    # Sprint B / LGPD: armazenado encriptado (Fernet). 512 chars cobrem nomes
    # longos após Fernet (ciphertext ~140 bytes pra strings curtas).
    full_name: Mapped[str] = mapped_column(String(512))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
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
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # M2 — TOTP 2FA. Secret is stored Fernet-encrypted; NULL means 2FA not enrolled.
    totp_secret_enc: Mapped[str | None] = mapped_column(String(512), nullable=True)
    totp_enabled: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0")

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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # M6 — TTL 30 days for pending invites; NULL means no expiry (accepted/revoked rows).
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)


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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class DailyCheckIn(Base):
    __tablename__ = "daily_checkins"
    __table_args__ = (
        Index("ix_checkins_patient_created", "patient_id", "created_at"),
        Index("ix_checkins_patient_deleted", "patient_id", "deleted_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    # B6 — soft delete: NULL = active, non-NULL = deleted. Hard DELETE is never
    # used so clinical history is retained for audit (LGPD Art. 37).
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
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
    __table_args__ = (
        Index("ix_assessments_patient_created", "patient_id", "created_at"),
        Index("ix_assessments_patient_deleted", "patient_id", "deleted_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    # N-C2 — soft delete for LGPD compliance
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    scale_name: Mapped[str] = mapped_column(String(32))
    answers_json: Mapped[str] = mapped_column(Text)
    score: Mapped[int] = mapped_column(Integer)
    interpretation: Mapped[str] = mapped_column(String(255))

    patient: Mapped[User] = relationship(back_populates="assessments")


class ClinicalAlert(Base):
    __tablename__ = "clinical_alerts"
    __table_args__ = (
        Index("ix_alerts_patient_created", "patient_id", "created_at"),
        Index("ix_alerts_patient_deleted", "patient_id", "deleted_at"),
        Index("ix_alerts_type_target", "alert_type", "escalation_target"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    # B6 — soft delete
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    level: Mapped[str] = mapped_column(String(32))
    alert_type: Mapped[str] = mapped_column(
        String(64),
        default=AlertType.psychiatric_emergency.value,
        server_default=AlertType.psychiatric_emergency.value,
        nullable=False,
    )
    escalation_target: Mapped[str] = mapped_column(
        String(64),
        default=EscalationTarget.clinician_caregiver_now.value,
        server_default=EscalationTarget.clinician_caregiver_now.value,
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(255))
    message: Mapped[str] = mapped_column(Text)
    acknowledged: Mapped[bool] = mapped_column(Boolean, default=False)


class ClinicalReport(Base):
    __tablename__ = "clinical_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    # B6 — soft delete
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class RevokedAccessToken(Base):
    """Blacklist of access-token JTIs that should be rejected before they
    expire naturally. Logout adds the current bearer's jti so a stolen access
    token can be killed inside its 30-minute TTL window (Sprint 14 / S34)."""

    __tablename__ = "revoked_access_tokens"

    jti: Mapped[str] = mapped_column(String(64), primary_key=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ConsentPurpose(str, Enum):
    """Sprint B / LGPD Art. 7 II + Art. 9: consentimento separado por
    finalidade. O paciente pode revogar uma sem afetar as outras."""
    clinical_data_storage = "clinical_data_storage"
    clinician_sharing = "clinician_sharing"
    caregiver_sharing = "caregiver_sharing"
    research_anonymized = "research_anonymized"
    # M4 — biometric processing for local on-device analysis (FaceID/TouchID).
    biometric_processing = "biometric_processing"


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
    granted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class RiskCache(Base):
    """M9 — Precomputed risk score per patient. Updated synchronously after
    every check-in so /clinician/patients reads from cache instead of running
    the full scoring algorithm on every request."""
    __tablename__ = "risk_cache"

    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    risk_score: Mapped[int] = mapped_column(Integer, default=0)
    risk_level: Mapped[str] = mapped_column(String(32), default="low")
    computed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class TotpPendingSession(Base):
    """M2 — Short-lived session created when a TOTP-enabled user passes the
    password check but has not yet submitted the OTP code. Consumed exactly
    once by POST /auth/2fa/verify."""
    __tablename__ = "totp_pending_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    session_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class BaselineMetric(str, Enum):
    """Metrics we roll a personal baseline over. Fixed enum so downstream
    consumers (episode pipeline, insights) can reason about semantics without
    string matching."""
    mood = "mood"
    anxiety = "anxiety"
    energy = "energy"
    irritability = "irritability"
    sleep_hours = "sleep_hours"


class UserBaseline(Base):
    """Rolling personal baseline per (patient, metric). Recomputed after each
    check-in from the last 60 days. Enables "your HRV is 15% below *your*
    normal" instead of population-level thresholds — the substrate for the
    personalized-insight loop that drives retention."""
    __tablename__ = "user_baselines"
    __table_args__ = (
        UniqueConstraint("patient_id", "metric", name="uq_user_baseline_metric"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    metric: Mapped[str] = mapped_column(String(32))
    window_days: Mapped[int] = mapped_column(Integer, default=60, server_default="60")
    sample_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    mean_value: Mapped[float] = mapped_column(Float, default=0.0, server_default="0")
    stdev_value: Mapped[float] = mapped_column(Float, default=0.0, server_default="0")
    current_value: Mapped[float] = mapped_column(Float, default=0.0, server_default="0")
    computed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class InterventionType(str, Enum):
    """Catalogued intervention families. Kept small on purpose — insights need
    enough samples per bucket to be statistically meaningful. Add sparingly."""
    breathing = "breathing"
    walk = "walk"
    sleep_hygiene = "sleep_hygiene"
    journaling = "journaling"
    medication_adherence = "medication_adherence"
    social_contact = "social_contact"
    mindfulness = "mindfulness"
    therapy_technique = "therapy_technique"


class InterventionTriggerSource(str, Enum):
    user_manual = "user_manual"
    alert = "alert"
    app_suggestion = "app_suggestion"


class InterventionLog(Base):
    """Records that a patient used (or committed to) an intervention. The
    baseline snapshot at trigger time is stored inline so the outcome delta
    can be computed even after subsequent check-ins shift the rolling mean.

    Notes are optional free-text (encrypted at rest — treated as PHI). Outcome
    fields stay NULL until enough post-trigger check-ins arrive to compute a
    delta (see interventions.compute_pending_outcomes)."""
    __tablename__ = "intervention_logs"
    __table_args__ = (
        Index("ix_intervention_logs_patient_created", "patient_id", "triggered_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    intervention_type: Mapped[str] = mapped_column(String(64))
    trigger_source: Mapped[str] = mapped_column(
        String(32),
        default=InterventionTriggerSource.user_manual.value,
        server_default=InterventionTriggerSource.user_manual.value,
    )
    triggered_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    baseline_snapshot_json: Mapped[str] = mapped_column(Text, default="{}", server_default="{}")
    notes_encrypted: Mapped[str] = mapped_column(Text, default="", server_default="")
    outcome_computed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    outcome_delta_json: Mapped[str | None] = mapped_column(Text, nullable=True)
