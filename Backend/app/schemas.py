from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, EmailStr, Field, model_validator


Role = Literal["patient", "clinician"]


# Sprint B: validador único de senha. Antes era só `min_length=8` → "12345678"
# passava. max_length=128 defende o bcrypt contra DoS com payload de 10MB
# (bcrypt 3.x trunca em 72 bytes mas a hash inteira ainda processa o input).
def _validate_password_complexity(value: str) -> str:
    if len(value) > 128:
        raise ValueError("Senha não pode ter mais de 128 caracteres")
    has_letter = any(c.isalpha() for c in value)
    has_digit = any(c.isdigit() for c in value)
    if not (has_letter and has_digit):
        raise ValueError(
            "Senha precisa conter ao menos uma letra e um dígito"
        )
    return value


PasswordField = Annotated[
    str,
    Field(min_length=8, max_length=128),
    AfterValidator(_validate_password_complexity),
]


class UserCreate(BaseModel):
    """Self-service signup. Always creates a patient account; clinician
    promotion is gated behind the admin endpoint."""

    email: EmailStr
    password: PasswordField
    full_name: str = Field(min_length=1, max_length=255)


class AdminPromoteRequest(BaseModel):
    role: Role


class AdminPurgeResponse(BaseModel):
    deleted_refresh_tokens: int
    deleted_access_token_jtis: int = 0
    deleted_password_reset_tokens: int = 0
    deleted_totp_pending_sessions: int = 0
    deleted_expired_invites: int = 0


class AdminRevokeSessionsResponse(BaseModel):
    user_id: int
    new_token_epoch: int
    revoked_refresh_tokens: int


class ClinicianInviteCreate(BaseModel):
    patient_email: EmailStr


class ClinicianInviteRead(BaseModel):
    id: int
    clinician_id: int
    patient_id: int
    clinician_full_name: str
    clinician_email: EmailStr
    status: Literal["pending", "accepted", "revoked"]
    created_at: datetime

    model_config = {"from_attributes": True}


class LinkedClinicianRead(BaseModel):
    """Clinician the patient is currently sharing data with. Returned by
    GET /me/linked-clinicians so the patient can revoke access without
    needing to dig through the invites log."""

    clinician_id: int
    clinician_full_name: str
    clinician_email: EmailStr
    linked_at: datetime

    model_config = {"from_attributes": True}


class ClinicianSentInviteRead(BaseModel):
    """Same record as ClinicianInviteRead but enriched with the patient's
    public profile fields so the clinician dashboard can display feedback
    on invites they sent — including the ones the patient revoked."""

    id: int
    patient_id: int
    patient_full_name: str
    patient_email: EmailStr
    status: Literal["pending", "accepted", "revoked"]
    created_at: datetime

    model_config = {"from_attributes": True}


class UserRead(BaseModel):
    id: int
    email: EmailStr
    full_name: str
    role: Role
    created_at: datetime
    risk_score: int | None = None
    risk_level: str | None = None

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    """Sprint B: retificação de cadastro (LGPD Art. 18 III). Apenas full_name e
    email são editáveis pelo titular — papel (role) é gerenciado pelo admin,
    senha tem fluxo próprio."""
    full_name: str | None = Field(default=None, min_length=1, max_length=255)
    email: EmailStr | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class PasswordResetRequest(BaseModel):
    email: EmailStr


class PasswordResetConfirm(BaseModel):
    email: EmailStr
    reset_code: str = Field(min_length=8)
    new_password: PasswordField


class MessageResponse(BaseModel):
    message: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserRead


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=8)


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=8)


# M2 — 2FA TOTP schemas

class TotpSetupResponse(BaseModel):
    secret: str
    provisioning_uri: str


class TotpConfirmRequest(BaseModel):
    code: str = Field(min_length=6, max_length=8)


class TotpVerifyRequest(BaseModel):
    pending_session_id: str = Field(min_length=8)
    code: str = Field(min_length=6, max_length=8)


class LoginResponse(BaseModel):
    """Returned by /auth/login. If requires_totp is True, the client must
    complete the TOTP step via /auth/2fa/verify using pending_session_id.
    When requires_totp is False the fields mirror TokenResponse."""
    access_token: str | None = None
    refresh_token: str | None = None
    token_type: str = "bearer"
    user: "UserRead | None" = None
    requires_totp: bool = False
    pending_session_id: str | None = None


class LinkPatientRequest(BaseModel):
    patient_email: EmailStr


class CaregiverContactCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    contact: str = Field(min_length=3, max_length=255)
    relationship: str = ""
    share_enabled: bool = False


class CaregiverContactRead(BaseModel):
    id: int
    patient_id: int
    name: str
    contact: str
    relationship: str
    share_enabled: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class DailyCheckInCreate(BaseModel):
    mood: float = Field(ge=0, le=5)
    anxiety: float = Field(ge=0, le=5)
    energy: float = Field(ge=0, le=5)
    irritability: float = Field(ge=0, le=5)
    sleep_hours: float = Field(ge=0, le=24)
    appetite: float = Field(ge=0, le=5)
    libido: float = Field(ge=0, le=5)
    medication_taken: bool
    side_effects: str = Field(default="", max_length=2000)
    automatic_thoughts: str = Field(default="", max_length=2000)
    suicidal_ideation: bool = False
    journal_entry: str = Field(default="", max_length=5000)


class DailyCheckInRead(DailyCheckInCreate):
    id: int
    patient_id: int
    created_at: datetime

    model_config = {"from_attributes": True}


class ScaleAssessmentCreate(BaseModel):
    patient_id: int | None = None
    scale_name: Literal["PHQ-9", "GAD-7", "YMRS"]
    answers: list[int]
    score: int
    interpretation: str

    @model_validator(mode="after")
    def validate_answer_count(self) -> "ScaleAssessmentCreate":
        _expected = {"PHQ-9": 9, "GAD-7": 7, "YMRS": 11}
        expected = _expected[self.scale_name]
        if len(self.answers) != expected:
            raise ValueError(
                f"{self.scale_name} requires exactly {expected} answers, "
                f"got {len(self.answers)}"
            )
        # YMRS items 5-8 (0-indexed 4-7) can each score 0-8; the global cap is 8.
        _valid_range = {"PHQ-9": (0, 3), "GAD-7": (0, 3), "YMRS": (0, 8)}
        lo, hi = _valid_range[self.scale_name]
        out_of_range = [a for a in self.answers if not (lo <= a <= hi)]
        if out_of_range:
            raise ValueError(
                f"{self.scale_name} answers must be between {lo} and {hi}, "
                f"got out-of-range values: {out_of_range}"
            )
        return self


class ScaleAssessmentRead(BaseModel):
    id: int
    patient_id: int
    created_at: datetime
    scale_name: str
    answers: list[int]
    score: int
    interpretation: str


class ClinicalAlertRead(BaseModel):
    id: int
    patient_id: int
    created_at: datetime
    level: str
    title: str
    message: str
    acknowledged: bool

    model_config = {"from_attributes": True}


class ClinicalReportCreate(BaseModel):
    patient_id: int | None = None
    risk_level: str
    summary: str
    auto_send: bool = False
    care_team_contact: str | None = None
    apns_token: str | None = None


class ClinicalReportRead(BaseModel):
    id: int
    patient_id: int
    created_at: datetime
    risk_level: str
    summary: str

    model_config = {"from_attributes": True}


class DeviceTokenCreate(BaseModel):
    token: str = Field(min_length=8)
    platform: str = "ios"


class DeviceTokenRead(BaseModel):
    id: int
    user_id: int
    token: str
    platform: str
    created_at: datetime

    model_config = {"from_attributes": True}


class AuditLogRead(BaseModel):
    id: int
    actor_user_id: int | None = None
    action: str
    resource_type: str
    resource_id: str
    created_at: datetime

    model_config = {"from_attributes": True}


class NotificationLogRead(BaseModel):
    id: int
    patient_id: int
    recipient: str
    channel: str
    event_type: str
    status: str
    detail: str
    created_at: datetime

    model_config = {"from_attributes": True}


class AccountExportRead(BaseModel):
    user: UserRead
    checkins: list[DailyCheckInRead]
    assessments: list[ScaleAssessmentRead]
    alerts: list[ClinicalAlertRead]
    reports: list[ClinicalReportRead]
    audit_logs: list[AuditLogRead]
    notification_logs: list[NotificationLogRead]


class RetentionDeleteResponse(BaseModel):
    deleted_checkins: int
    deleted_assessments: int
    deleted_alerts: int
    deleted_reports: int


class AccountDeleteResponse(BaseModel):
    deleted_user_id: int
    message: str


# Sprint B / LGPD: Consent explícito por finalidade.
ConsentPurposeLiteral = Literal[
    "clinical_data_storage",
    "clinician_sharing",
    "caregiver_sharing",
    "research_anonymized",
    "biometric_processing",  # M4 — local FaceID/TouchID on-device analysis
]


class ConsentGrantRequest(BaseModel):
    purpose: ConsentPurposeLiteral
    policy_version: str = Field(default="", max_length=32)


class ConsentRead(BaseModel):
    id: int
    purpose: ConsentPurposeLiteral
    granted_at: datetime
    revoked_at: datetime | None = None
    policy_version: str
    active: bool

    model_config = {"from_attributes": True}


class PatientListResponse(BaseModel):
    items: list[UserRead]
    total: int
    skip: int
    limit: int
