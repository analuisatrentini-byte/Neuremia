"""Domain service helpers shared by every router.

Kept here so routers can reach for them without pulling in `main.py` (which
would create cycles) and so they remain testable in isolation.
"""
import json
from collections import defaultdict
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import models, schemas
from .notifications import notifications
from .security import create_access_token, decrypt_field, encrypt_field, generate_refresh_token


def utcnow() -> datetime:
    """Naive UTC datetime for comparison with SQLite DateTime columns.

    SQLAlchemy + SQLite returns naive datetimes even with DateTime(timezone=True).
    Using utcnow() directly in comparisons causes TypeError.
    This helper returns a naive UTC datetime that safely compares with DB values.
    In production (PostgreSQL), DateTime(timezone=True) returns tz-aware values,
    but the comparison still works because naive < aware raises TypeError only on
    mixed comparisons — Postgres columns come back aware, so use datetime.now(tz).
    """
    # For SQLite compat, return naive. For Postgres, both sides are aware/naive
    # consistently so this is fine in both environments.
    return datetime.now(timezone.utc).replace(tzinfo=None)


# Sprint B / LGPD: helpers para PHI encriptado at rest. `user.full_name` e
# `caregiver_contacts.contact` agora são Fernet ciphertext na coluna; toda
# leitura passa por aqui pra apresentar plaintext, toda escrita passa por
# encrypt_field nos endpoints.
def decrypted_full_name(user: models.User | None) -> str:
    if user is None or not user.full_name:
        return ""
    return decrypt_field(user.full_name)


def decrypted_caregiver_contact(caregiver: models.CaregiverContact) -> str:
    if not caregiver.contact:
        return ""
    return decrypt_field(caregiver.contact)


def caregiver_read(caregiver: models.CaregiverContact) -> schemas.CaregiverContactRead:
    return schemas.CaregiverContactRead(
        id=caregiver.id,
        patient_id=caregiver.patient_id,
        name=caregiver.name,
        contact=decrypted_caregiver_contact(caregiver),
        relationship=caregiver.relationship,
        share_enabled=caregiver.share_enabled,
        created_at=caregiver.created_at,
    )


# ---------------------------------------------------------------------- audit


def audit(
    db: Session,
    actor: models.User,
    action: str,
    resource_type: str,
    resource_id: str,
) -> None:
    """Append an audit-log row in the current transaction. Caller commits."""
    db.add(models.AuditLog(
        actor_user_id=actor.id,
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
    ))


def issue_token_pair(db: Session, user: models.User) -> tuple[str, str]:
    """Mint an access token and a fresh refresh token. Refresh token is
    persisted as a SHA-256 hash; the raw value is returned to the caller
    once.

    M5 — also prunes already-expired refresh tokens for this user to keep
    the table lean without a background cron. Revoked tokens whose
    revoked_at is older than REFRESH_TOKEN_EXPIRE_DAYS are also cleaned up."""
    now = utcnow()
    db.query(models.RefreshToken).filter(
        models.RefreshToken.user_id == user.id,
        models.RefreshToken.expires_at < now,
    ).delete(synchronize_session=False)

    raw_refresh, digest, expires_at = generate_refresh_token()
    db.add(models.RefreshToken(
        user_id=user.id,
        token_hash=digest,
        expires_at=expires_at,
    ))
    access, _jti = create_access_token(str(user.id), epoch=user.token_epoch)
    return access, raw_refresh


def log_notification(
    db: Session,
    patient_id: int,
    recipient: str,
    channel: str,
    event_type: str,
    sent: bool,
    detail: str = "",
) -> None:
    db.add(models.NotificationLog(
        patient_id=patient_id,
        recipient=recipient,
        channel=channel,
        event_type=event_type,
        status="sent" if sent else "failed",
        detail=detail,
    ))


# ------------------------------------------------------------ access control


def can_access_patient(db: Session, user: models.User, patient_id: int) -> bool:
    if user.role == models.UserRole.patient.value:
        return user.id == patient_id

    return db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.clinician_id == user.id,
        models.ClinicianPatientLink.patient_id == patient_id,
    ).first() is not None


def has_active_consent(db: Session, user_id: int, purpose: str) -> bool:
    """Returns True iff the user has a non-revoked consent record for purpose."""
    return db.query(models.Consent).filter(
        models.Consent.user_id == user_id,
        models.Consent.purpose == purpose,
        models.Consent.revoked_at.is_(None),
    ).first() is not None


# ------------------------------------------------------------- DTO assemblers


def checkin_read(checkin: models.DailyCheckIn) -> schemas.DailyCheckInRead:
    return schemas.DailyCheckInRead(
        id=checkin.id,
        patient_id=checkin.patient_id,
        created_at=checkin.created_at,
        mood=checkin.mood,
        anxiety=checkin.anxiety,
        energy=checkin.energy,
        irritability=checkin.irritability,
        sleep_hours=checkin.sleep_hours,
        appetite=checkin.appetite,
        libido=checkin.libido,
        medication_taken=checkin.medication_taken,
        side_effects=decrypt_field(checkin.side_effects),
        automatic_thoughts=decrypt_field(checkin.automatic_thoughts),
        suicidal_ideation=checkin.suicidal_ideation,
        journal_entry=decrypt_field(checkin.journal_entry),
    )


def alert_read(alert: models.ClinicalAlert) -> schemas.ClinicalAlertRead:
    return schemas.ClinicalAlertRead(
        id=alert.id,
        patient_id=alert.patient_id,
        created_at=alert.created_at,
        level=alert.level,
        title=alert.title,
        message=decrypt_field(alert.message),
        acknowledged=alert.acknowledged,
    )


def report_read(report: models.ClinicalReport) -> schemas.ClinicalReportRead:
    return schemas.ClinicalReportRead(
        id=report.id,
        patient_id=report.patient_id,
        created_at=report.created_at,
        risk_level=report.risk_level,
        summary=decrypt_field(report.summary),
    )


def assessment_read(assessment: models.ScaleAssessment) -> schemas.ScaleAssessmentRead:
    return schemas.ScaleAssessmentRead(
        id=assessment.id,
        patient_id=assessment.patient_id,
        created_at=assessment.created_at,
        scale_name=assessment.scale_name,
        answers=json.loads(assessment.answers_json),
        score=assessment.score,
        interpretation=assessment.interpretation,
    )


def invite_read(db: Session, invite: models.ClinicianPatientInvite) -> schemas.ClinicianInviteRead:
    clinician = db.query(models.User).filter(models.User.id == invite.clinician_id).first()
    return schemas.ClinicianInviteRead(
        id=invite.id,
        clinician_id=invite.clinician_id,
        patient_id=invite.patient_id,
        clinician_full_name=decrypted_full_name(clinician),
        clinician_email=clinician.email if clinician else "",
        status=invite.status,
        created_at=invite.created_at,
    )


def sent_invite_read(db: Session, invite: models.ClinicianPatientInvite) -> schemas.ClinicianSentInviteRead:
    patient = db.query(models.User).filter(models.User.id == invite.patient_id).first()
    return schemas.ClinicianSentInviteRead(
        id=invite.id,
        patient_id=invite.patient_id,
        patient_full_name=decrypted_full_name(patient),
        patient_email=patient.email if patient else "",
        status=invite.status,
        created_at=invite.created_at,
    )


def invite_read_batch(
    db: Session,
    invites: list[models.ClinicianPatientInvite],
) -> list[schemas.ClinicianInviteRead]:
    """M3 — batch clinician lookup: one query instead of N."""
    clinician_ids = list({inv.clinician_id for inv in invites})
    clinicians = {
        u.id: u
        for u in db.query(models.User).filter(models.User.id.in_(clinician_ids)).all()
    }
    results = []
    for invite in invites:
        clinician = clinicians.get(invite.clinician_id)
        results.append(schemas.ClinicianInviteRead(
            id=invite.id,
            clinician_id=invite.clinician_id,
            patient_id=invite.patient_id,
            clinician_full_name=decrypted_full_name(clinician),
            clinician_email=clinician.email if clinician else "",
            status=invite.status,
            created_at=invite.created_at,
        ))
    return results


def sent_invite_read_batch(
    db: Session,
    invites: list[models.ClinicianPatientInvite],
) -> list[schemas.ClinicianSentInviteRead]:
    """M3 — batch patient lookup: one query instead of N."""
    patient_ids = list({inv.patient_id for inv in invites})
    patients = {
        u.id: u
        for u in db.query(models.User).filter(models.User.id.in_(patient_ids)).all()
    }
    results = []
    for invite in invites:
        patient = patients.get(invite.patient_id)
        results.append(schemas.ClinicianSentInviteRead(
            id=invite.id,
            patient_id=invite.patient_id,
            patient_full_name=decrypted_full_name(patient),
            patient_email=patient.email if patient else "",
            status=invite.status,
            created_at=invite.created_at,
        ))
    return results


# --------------------------------------------------------------- risk scoring


def _compute_risk_from_records(
    checkins: list[models.DailyCheckIn],
    assessments: list[models.ScaleAssessment],
    alerts: list[models.ClinicalAlert],
) -> tuple[int, str]:
    """Pure scoring function shared by single-patient and batched paths."""
    score = 0.0
    if checkins:
        latest = checkins[0]
        if latest.suicidal_ideation:
            score += 35
        if latest.mood <= 2:
            score += 16
        if latest.anxiety >= 4:
            score += 14
        if latest.sleep_hours < 6:
            score += 12
        if not latest.medication_taken:
            score += 10

        recent = checkins[:7]
        if len(recent) >= 3:
            first = recent[-1]
            if latest.mood <= first.mood - 1:
                score += 8
            if latest.anxiety >= first.anxiety + 1:
                score += 8
            if latest.sleep_hours <= first.sleep_hours - 1.5:
                score += 7
            missed = sum(1 for item in recent if not item.medication_taken)
            score += min(missed * 4, 12)

    for assessment in assessments[:3]:
        if assessment.scale_name == "PHQ-9":
            score += min((assessment.score / 27) * 12, 12)
        elif assessment.scale_name == "GAD-7":
            score += min((assessment.score / 21) * 10, 10)
        elif assessment.scale_name == "YMRS":
            score += min((assessment.score / 60) * 10, 10)

    for alert in alerts:
        score += 16 if alert.level == "high" else 8

    bounded_score = int(min(max(round(score), 0), 100))

    # Clinical override: certain individual signals are unconditionally HIGH
    # regardless of the aggregate score. These thresholds mirror the iOS-side
    # check-in alert logic (checkins.py) and the ClinicalThresholds constants
    # in the Swift client so that both surfaces agree on severity.
    if checkins:
        latest = checkins[0]
        if (
            latest.suicidal_ideation
            or latest.mood <= 1.0     # ClinicalThresholds.moodHighRisk
            or latest.anxiety >= 4.5  # ClinicalThresholds.anxietyHighRisk
        ):
            return max(bounded_score, 66), "high"

    if bounded_score >= 66:
        return bounded_score, "high"
    if bounded_score >= 34:
        return bounded_score, "moderate"
    return bounded_score, "low"


# --------------------------------------------------------- M9: RiskCache helpers


def update_risk_cache(db: Session, patient_id: int) -> None:
    """Recompute and persist risk score for one patient. Called synchronously
    after every check-in so /clinician/patients reads from cache."""
    from datetime import datetime, timezone
    score, level = patient_risk_summary_live(db, patient_id)
    cache = db.query(models.RiskCache).filter(
        models.RiskCache.patient_id == patient_id
    ).first()
    if cache is None:
        db.add(models.RiskCache(
            patient_id=patient_id,
            risk_score=score,
            risk_level=level,
            computed_at=utcnow(),
        ))
    else:
        cache.risk_score = score
        cache.risk_level = level
        cache.computed_at = utcnow()


def risk_from_cache_batch(
    db: Session, patient_ids: list[int]
) -> dict[int, tuple[int, str]]:
    """Read cached risk scores. Falls back to live computation for any patient
    not yet in the cache (e.g. first check-in not yet processed)."""
    if not patient_ids:
        return {}
    cached = {
        row.patient_id: (row.risk_score, row.risk_level)
        for row in db.query(models.RiskCache).filter(
            models.RiskCache.patient_id.in_(patient_ids)
        ).all()
    }
    missing = [pid for pid in patient_ids if pid not in cached]
    for pid in missing:
        cached[pid] = patient_risk_summary_live(db, pid)
    return cached


def patient_risk_summary(db: Session, patient_id: int) -> tuple[int, str]:
    """Public alias — reads from cache when available, live otherwise."""
    cache = db.query(models.RiskCache).filter(
        models.RiskCache.patient_id == patient_id
    ).first()
    if cache is not None:
        return cache.risk_score, cache.risk_level
    return patient_risk_summary_live(db, patient_id)


def patient_risk_summary_live(db: Session, patient_id: int) -> tuple[int, str]:
    checkins = (
        db.query(models.DailyCheckIn)
        .filter(
            models.DailyCheckIn.patient_id == patient_id,
            models.DailyCheckIn.deleted_at.is_(None),  # B6
        )
        .order_by(models.DailyCheckIn.created_at.desc())
        .limit(30)
        .all()
    )
    assessments = (
        db.query(models.ScaleAssessment)
        .filter(models.ScaleAssessment.patient_id == patient_id)
        .order_by(models.ScaleAssessment.created_at.desc())
        .limit(6)
        .all()
    )
    alerts = (
        db.query(models.ClinicalAlert)
        .filter(
            models.ClinicalAlert.patient_id == patient_id,
            models.ClinicalAlert.acknowledged == False,  # noqa: E712
            models.ClinicalAlert.deleted_at.is_(None),  # B6
        )
        .all()
    )
    return _compute_risk_from_records(checkins, assessments, alerts)


def _top_n_per_patient(db: Session, model, patient_ids: list[int], n: int):
    """Up to `n` newest rows of `model` per patient via a window function.
    Avoids fetching every row and truncating in Python (B29/P10)."""
    rn_column = func.row_number().over(
        partition_by=model.patient_id,
        order_by=model.created_at.desc(),
    ).label("rn")

    base_where = [model.patient_id.in_(patient_ids)]
    # B6 — exclude soft-deleted rows from ranking window when the model has deleted_at.
    if hasattr(model, "deleted_at"):
        base_where.append(model.deleted_at.is_(None))

    ranked = (
        select(model.id, rn_column)
        .where(*base_where)
        .subquery()
    )
    stmt = (
        select(model)
        .join(ranked, model.id == ranked.c.id)
        .where(ranked.c.rn <= n)
        .order_by(model.patient_id, model.created_at.desc())
    )
    return db.execute(stmt).scalars().all()


def patient_risk_summary_batch(
    db: Session, patient_ids: list[int]
) -> dict[int, tuple[int, str]]:
    """M9 — read from RiskCache, falling back to live computation for new patients."""
    return risk_from_cache_batch(db, patient_ids)


def _patient_risk_summary_batch_live(
    db: Session, patient_ids: list[int]
) -> dict[int, tuple[int, str]]:
    """Compute risk for many patients in 3 queries instead of 3*N (Sprint 13)."""
    if not patient_ids:
        return {}

    checkins_by_patient: dict[int, list[models.DailyCheckIn]] = defaultdict(list)
    for ci in _top_n_per_patient(db, models.DailyCheckIn, patient_ids, 30):
        checkins_by_patient[ci.patient_id].append(ci)

    assessments_by_patient: dict[int, list[models.ScaleAssessment]] = defaultdict(list)
    for assessment in _top_n_per_patient(db, models.ScaleAssessment, patient_ids, 6):
        assessments_by_patient[assessment.patient_id].append(assessment)

    alerts_by_patient: dict[int, list[models.ClinicalAlert]] = defaultdict(list)
    for alert in (
        db.query(models.ClinicalAlert)
        .filter(
            models.ClinicalAlert.patient_id.in_(patient_ids),
            models.ClinicalAlert.acknowledged == False,  # noqa: E712
            models.ClinicalAlert.deleted_at.is_(None),  # B6
        )
        .all()
    ):
        alerts_by_patient[alert.patient_id].append(alert)

    return {
        pid: _compute_risk_from_records(
            checkins_by_patient.get(pid, []),
            assessments_by_patient.get(pid, []),
            alerts_by_patient.get(pid, []),
        )
        for pid in patient_ids
    }


def user_read(db: Session, user: models.User, include_risk: bool = False) -> schemas.UserRead:
    risk_score = None
    risk_level = None
    if include_risk and user.role == models.UserRole.patient.value:
        risk_score, risk_level = patient_risk_summary(db, user.id)

    return schemas.UserRead(
        id=user.id,
        email=user.email,
        full_name=decrypted_full_name(user),
        role=user.role,
        created_at=user.created_at,
        risk_score=risk_score,
        risk_level=risk_level,
    )


# ----------------------------------------------------------- notifications fan-out


def notify_enabled_caregivers(
    db: Session,
    patient: models.User,
    title: str,
    message: str,
    event_type: str,
) -> None:
    caregivers = db.query(models.CaregiverContact).filter(
        models.CaregiverContact.patient_id == patient.id,
        models.CaregiverContact.share_enabled == True,  # noqa: E712
    ).all()
    patient_name = decrypted_full_name(patient)
    for caregiver in caregivers:
        # Sprint B: contact é ciphertext na coluna; decripta só pra envio SMTP.
        recipient = decrypted_caregiver_contact(caregiver)
        try:
            sent = notifications.send_clinical_alert_email(
                recipient, patient_name, title, message
            )
            log_notification(db, patient.id, recipient, "email", event_type, sent, title)
        except Exception:
            log_notification(db, patient.id, recipient, "email", event_type, False, "exception")


def notify_linked_clinicians(
    db: Session,
    patient: models.User,
    title: str,
    message: str,
) -> None:
    links = db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.patient_id == patient.id
    ).all()
    clinician_ids = [link.clinician_id for link in links]
    if not clinician_ids:
        notify_enabled_caregivers(db, patient, title, message, event_type="clinical_alert")
        return

    clinicians = db.query(models.User).filter(models.User.id.in_(clinician_ids)).all()
    patient_name = decrypted_full_name(patient)
    for clinician in clinicians:
        try:
            sent_email = notifications.send_clinical_alert_email(
                clinician.email, patient_name, title, message
            )
            log_notification(db, patient.id, clinician.email, "email", "clinical_alert", sent_email, title)
            tokens = db.query(models.DeviceToken).filter(models.DeviceToken.user_id == clinician.id).all()
            for token in tokens:
                # title/body are stripped inside send_push_webhook (PHI-safe).
                # Only event_type and patient_id survive the safe_data whitelist
                # so the clinician app can route to the right screen without
                # any clinical content leaving the authenticated channel.
                sent_push = notifications.send_push_webhook(
                    token.token,
                    "NeuroFlow",
                    "Nova atualizacao clinica",
                    data={
                        "event_type": "clinical_alert",
                        "patient_id": str(patient.id),
                    },
                )
                log_notification(
                    db, patient.id, f"{token.platform}:{token.id}",
                    "push", "clinical_alert", sent_push, title,
                )
        except Exception:
            audit(db, patient, "notification_failed", "user", str(clinician.id))

    notify_enabled_caregivers(db, patient, title, message, event_type="clinical_alert")


def notify_linked_clinicians_report(
    db: Session,
    patient: models.User,
    summary: str,
) -> None:
    links = db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.patient_id == patient.id
    ).all()
    clinician_ids = [link.clinician_id for link in links]
    if not clinician_ids:
        notify_enabled_caregivers(
            db, patient, "Relatório automático", summary, event_type="clinical_report"
        )
        return

    clinicians = db.query(models.User).filter(models.User.id.in_(clinician_ids)).all()
    patient_name = decrypted_full_name(patient)
    for clinician in clinicians:
        try:
            sent_email = notifications.send_clinical_report_email(
                clinician.email, patient_name, summary
            )
            log_notification(
                db, patient.id, clinician.email,
                "email", "clinical_report", sent_email, "automatic_report",
            )
            tokens = db.query(models.DeviceToken).filter(models.DeviceToken.user_id == clinician.id).all()
            for token in tokens:
                sent_push = notifications.send_push_webhook(
                    token.token,
                    "NeuroFlow",
                    "Novo relatorio clinico disponivel",
                    data={
                        "event_type": "clinical_report",
                        "patient_id": str(patient.id),
                    },
                )
                log_notification(
                    db, patient.id, f"{token.platform}:{token.id}",
                    "push", "clinical_report", sent_push, "automatic_report",
                )
        except Exception:
            audit(db, patient, "report_notification_failed", "user", str(clinician.id))

    notify_enabled_caregivers(
        db, patient, "Relatório automático", summary, event_type="clinical_report"
    )
