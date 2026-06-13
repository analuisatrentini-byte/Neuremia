"""/me/* — endpoints scoped to the authenticated patient."""
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user, require_role
from ..security import encrypt_field
from ..services import (
    alert_read,
    assessment_read,
    audit,
    checkin_read,
    decrypted_full_name,
    invite_read,
    invite_read_batch,
    report_read,
    user_read,
    utcnow,
)

# Maximum number of check-in records returned in a single export to prevent
# timeouts and oversized payloads. ~500 check-ins ≈ 500 days ≈ 16+ months.
_EXPORT_CHECKINS_MAX = 500
_EXPORT_OTHER_MAX = 200


router = APIRouter(prefix="/me", tags=["me"])


@router.get("", response_model=schemas.UserRead)
def me(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    # Sprint B: decripta full_name antes de devolver pra cliente.
    return user_read(db, user)


# Sprint B (LGPD Art. 18 III — direito à retificação): permite o titular
# atualizar nome completo e email. Mudança de email checa colisão única —
# se o email já está em uso por outro user, retorna 409 sem revelar qual
# user (evita enumeration). Cada alteração gera entrada no audit_log.
@router.patch("", response_model=schemas.UserRead)
def update_me(
    payload: schemas.UserUpdate,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    changed = False
    if payload.full_name is not None and payload.full_name != decrypted_full_name(user):
        # Sprint B: full_name encriptado at rest.
        user.full_name = encrypt_field(payload.full_name)
        audit(db, user, "update_full_name", "user", str(user.id))
        changed = True

    if payload.email is not None and payload.email != user.email:
        conflict = (
            db.query(models.User)
            .filter(models.User.email == payload.email, models.User.id != user.id)
            .first()
        )
        if conflict is not None:
            raise HTTPException(status_code=409, detail="Email already in use")
        user.email = payload.email
        # Invalidate all existing sessions — email is an identity anchor.
        # Any token issued before this change is rejected by current_user epoch check.
        user.token_epoch = user.token_epoch + 1
        db.query(models.RefreshToken).filter(
            models.RefreshToken.user_id == user.id,
            models.RefreshToken.revoked_at.is_(None),
        ).update({models.RefreshToken.revoked_at: utcnow()}, synchronize_session=False)
        audit(db, user, "update_email", "user", str(user.id))
        changed = True

    if changed:
        db.commit()
        db.refresh(user)
    return user_read(db, user)


# Sprint B / LGPD Art. 7 II + Art. 9: consentimento explícito por finalidade.
# Granular o suficiente para o paciente revogar pesquisa anônima sem perder
# o cuidado clínico, ou parar compartilhamento com cuidador sem afetar
# integração com médico. Histórico de outorga e revogação fica auditável.
def _consent_read(consent: models.Consent) -> schemas.ConsentRead:
    return schemas.ConsentRead(
        id=consent.id,
        purpose=consent.purpose,
        granted_at=consent.granted_at,
        revoked_at=consent.revoked_at,
        policy_version=consent.policy_version,
        active=consent.revoked_at is None,
    )


@router.get("/consents", response_model=list[schemas.ConsentRead])
def list_my_consents(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    consents = (
        db.query(models.Consent)
        .filter(models.Consent.user_id == user.id)
        .order_by(models.Consent.granted_at.desc())
        .all()
    )
    return [_consent_read(c) for c in consents]


@router.post("/consents", response_model=schemas.ConsentRead)
def grant_consent(
    payload: schemas.ConsentGrantRequest,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    # Upsert: se já existe registro para a mesma finalidade, reativa.
    existing = (
        db.query(models.Consent)
        .filter(
            models.Consent.user_id == user.id,
            models.Consent.purpose == payload.purpose,
        )
        .first()
    )
    if existing is None:
        existing = models.Consent(
            user_id=user.id,
            purpose=payload.purpose,
            policy_version=payload.policy_version,
        )
        db.add(existing)
    else:
        existing.revoked_at = None
        existing.granted_at = utcnow()
        existing.policy_version = payload.policy_version
    audit(db, user, "grant_consent", "consent", payload.purpose)
    db.commit()
    db.refresh(existing)
    return _consent_read(existing)


@router.delete("/consents/{purpose}", response_model=schemas.ConsentRead)
def revoke_consent(
    purpose: schemas.ConsentPurposeLiteral,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    consent = (
        db.query(models.Consent)
        .filter(models.Consent.user_id == user.id, models.Consent.purpose == purpose)
        .first()
    )
    if consent is None:
        raise HTTPException(status_code=404, detail="Consent not found")
    if consent.revoked_at is None:
        consent.revoked_at = utcnow()
        audit(db, user, "revoke_consent", "consent", purpose)
        db.commit()
        db.refresh(consent)
    return _consent_read(consent)


@router.get("/audit-logs", response_model=list[schemas.AuditLogRead])
def my_audit_logs(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    logs = (
        db.query(models.AuditLog)
        .filter(models.AuditLog.actor_user_id == user.id)
        .order_by(models.AuditLog.created_at.desc())
        .limit(200)
        .all()
    )
    return logs


@router.get("/export", response_model=schemas.AccountExportRead)
def export_my_account(
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
    from_date: Optional[datetime] = Query(
        default=None,
        description="ISO-8601 UTC start date (inclusive). Omit for all records.",
        example="2025-01-01T00:00:00",
    ),
    to_date: Optional[datetime] = Query(
        default=None,
        description="ISO-8601 UTC end date (inclusive). Omit for all records.",
        example="2025-12-31T23:59:59",
    ),
):
    """Export the caller's data.

    Supports optional date-range filtering via ``from_date`` / ``to_date`` so
    that the iOS client can request a specific period without fetching all
    historical records (important after years of daily check-ins).

    Without filters the response is capped at ``_EXPORT_CHECKINS_MAX`` records
    (most-recent first) to prevent timeouts on large accounts. To export a full
    archive, iterate over yearly windows using ``from_date``/``to_date``.
    """
    if from_date and to_date and from_date > to_date:
        raise HTTPException(
            status_code=422,
            detail="from_date must be earlier than or equal to to_date",
        )

    def _date_filter(query, model):
        if from_date:
            query = query.filter(model.created_at >= from_date)
        if to_date:
            query = query.filter(model.created_at <= to_date)
        return query

    checkin_query = _date_filter(
        db.query(models.DailyCheckIn).filter(
            models.DailyCheckIn.patient_id == user.id,
            models.DailyCheckIn.deleted_at.is_(None),  # B6
        ),
        models.DailyCheckIn,
    ).order_by(models.DailyCheckIn.created_at.desc())

    # Apply hard cap only when no date window is requested. When the caller
    # provides a narrow window (e.g. one month) there is no risk of overflow.
    if from_date is None and to_date is None:
        checkin_query = checkin_query.limit(_EXPORT_CHECKINS_MAX)

    checkins = checkin_query.all()

    assessments = _date_filter(
        db.query(models.ScaleAssessment).filter(models.ScaleAssessment.patient_id == user.id),
        models.ScaleAssessment,
    ).order_by(models.ScaleAssessment.created_at.desc()).limit(_EXPORT_OTHER_MAX).all()

    alerts = _date_filter(
        db.query(models.ClinicalAlert).filter(
            models.ClinicalAlert.patient_id == user.id,
            models.ClinicalAlert.deleted_at.is_(None),  # B6
        ),
        models.ClinicalAlert,
    ).order_by(models.ClinicalAlert.created_at.desc()).limit(_EXPORT_OTHER_MAX).all()

    reports = _date_filter(
        db.query(models.ClinicalReport).filter(
            models.ClinicalReport.patient_id == user.id,
            models.ClinicalReport.deleted_at.is_(None),  # B6
        ),
        models.ClinicalReport,
    ).order_by(models.ClinicalReport.created_at.desc()).limit(_EXPORT_OTHER_MAX).all()

    logs = (
        db.query(models.AuditLog)
        .filter(models.AuditLog.actor_user_id == user.id)
        .order_by(models.AuditLog.created_at.desc())
        .limit(500)
        .all()
    )
    notification_logs = (
        db.query(models.NotificationLog)
        .filter(models.NotificationLog.patient_id == user.id)
        .order_by(models.NotificationLog.created_at.desc())
        .limit(500)
        .all()
    )
    audit(db, user, "export_account", "user", str(user.id))
    db.commit()
    return schemas.AccountExportRead(
        user=user_read(db, user),
        checkins=[checkin_read(item) for item in checkins],
        assessments=[assessment_read(item) for item in assessments],
        alerts=[alert_read(item) for item in alerts],
        reports=[report_read(item) for item in reports],
        audit_logs=logs,
        notification_logs=notification_logs,
    )


@router.delete("/clinical-data", response_model=schemas.RetentionDeleteResponse)
def delete_my_clinical_data(
    days_older_than: int = 365,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    cutoff = utcnow() - timedelta(days=max(days_older_than, 1))
    checkins = db.query(models.DailyCheckIn).filter(
        models.DailyCheckIn.patient_id == user.id,
        models.DailyCheckIn.created_at < cutoff,
    ).all()
    assessments = db.query(models.ScaleAssessment).filter(
        models.ScaleAssessment.patient_id == user.id,
        models.ScaleAssessment.created_at < cutoff,
    ).all()
    alerts = db.query(models.ClinicalAlert).filter(
        models.ClinicalAlert.patient_id == user.id,
        models.ClinicalAlert.created_at < cutoff,
    ).all()
    reports = db.query(models.ClinicalReport).filter(
        models.ClinicalReport.patient_id == user.id,
        models.ClinicalReport.created_at < cutoff,
    ).all()

    counts = (len(checkins), len(assessments), len(alerts), len(reports))
    for collection in (checkins, assessments, alerts, reports):
        for item in collection:
            db.delete(item)

    audit(db, user, "delete_old_clinical_data", "user", str(user.id))
    db.commit()
    return schemas.RetentionDeleteResponse(
        deleted_checkins=counts[0],
        deleted_assessments=counts[1],
        deleted_alerts=counts[2],
        deleted_reports=counts[3],
    )


@router.delete("", response_model=schemas.AccountDeleteResponse)
def delete_my_account(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    """Hard-delete the caller's account. Per-user tables CASCADE; AuditLog
    uses SET NULL (Sprint 15 / D4)."""
    deleted_user_id = user.id
    audit(db, user, "delete_account", "user", str(user.id))
    db.flush()
    db.delete(user)
    db.commit()
    return schemas.AccountDeleteResponse(
        deleted_user_id=deleted_user_id,
        message="Conta e dados locais do backend removidos.",
    )


@router.get("/linked-clinicians", response_model=list[schemas.LinkedClinicianRead])
def list_my_linked_clinicians(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    require_role(user, models.UserRole.patient.value)
    links = (
        db.query(models.ClinicianPatientLink)
        .filter(models.ClinicianPatientLink.patient_id == user.id)
        .order_by(models.ClinicianPatientLink.created_at.desc())
        .all()
    )
    clinician_ids = [link.clinician_id for link in links]
    if not clinician_ids:
        return []
    clinicians = {
        clinician.id: clinician
        for clinician in db.query(models.User).filter(models.User.id.in_(clinician_ids)).all()
    }
    result: list[schemas.LinkedClinicianRead] = []
    for link in links:
        clinician = clinicians.get(link.clinician_id)
        if clinician is None:
            continue
        result.append(
            schemas.LinkedClinicianRead(
                clinician_id=clinician.id,
                clinician_full_name=decrypted_full_name(clinician),
                clinician_email=clinician.email,
                linked_at=link.created_at,
            )
        )
    return result


@router.delete("/clinical-access/{clinician_id}", response_model=schemas.MessageResponse)
def revoke_clinician_access(
    clinician_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.patient.value)

    link = db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.clinician_id == clinician_id,
        models.ClinicianPatientLink.patient_id == user.id,
    ).first()
    if link is None:
        raise HTTPException(status_code=404, detail="Clinician not linked")

    db.delete(link)

    invites = db.query(models.ClinicianPatientInvite).filter(
        models.ClinicianPatientInvite.clinician_id == clinician_id,
        models.ClinicianPatientInvite.patient_id == user.id,
        models.ClinicianPatientInvite.status == models.InviteStatus.accepted.value,
    ).all()
    for invite in invites:
        invite.status = models.InviteStatus.revoked.value
        invite.decided_at = utcnow()

    # Increment clinician's token_epoch so any active JWT they hold is
    # immediately rejected by current_user — revocation takes effect instantly
    # instead of waiting for the 30-day refresh token TTL to expire.
    clinician = db.query(models.User).filter(models.User.id == clinician_id).first()
    if clinician is not None:
        clinician.token_epoch = clinician.token_epoch + 1
        db.query(models.RefreshToken).filter(
            models.RefreshToken.user_id == clinician_id,
            models.RefreshToken.revoked_at.is_(None),
        ).update({models.RefreshToken.revoked_at: utcnow()}, synchronize_session=False)

    audit(db, user, "revoke_clinician_access", "user", str(clinician_id))
    db.commit()
    return schemas.MessageResponse(message="Acesso do médico removido.")


@router.get("/invites", response_model=list[schemas.ClinicianInviteRead])
def list_my_invites(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    require_role(user, models.UserRole.patient.value)
    now = utcnow()
    invites = (
        db.query(models.ClinicianPatientInvite)
        .filter(
            models.ClinicianPatientInvite.patient_id == user.id,
            models.ClinicianPatientInvite.status == models.InviteStatus.pending.value,
            # M6: exclude expired invites (expires_at NULL = legacy row, keep visible)
            (models.ClinicianPatientInvite.expires_at.is_(None))
            | (models.ClinicianPatientInvite.expires_at > now),
        )
        .order_by(models.ClinicianPatientInvite.created_at.desc())
        .all()
    )
    return invite_read_batch(db, invites)


@router.post("/invites/{invite_id}/accept", response_model=schemas.ClinicianInviteRead)
def accept_clinician_invite(
    invite_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.patient.value)
    invite = db.query(models.ClinicianPatientInvite).filter(
        models.ClinicianPatientInvite.id == invite_id,
        models.ClinicianPatientInvite.patient_id == user.id,
        models.ClinicianPatientInvite.status == models.InviteStatus.pending.value,
    ).first()
    if invite is None:
        raise HTTPException(status_code=404, detail="Convite não encontrado")

    invite.status = models.InviteStatus.accepted.value
    invite.decided_at = utcnow()

    existing_link = db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.clinician_id == invite.clinician_id,
        models.ClinicianPatientLink.patient_id == user.id,
    ).first()
    if existing_link is None:
        db.add(models.ClinicianPatientLink(
            clinician_id=invite.clinician_id, patient_id=user.id
        ))

    audit(db, user, "accept_clinician_invite", "user", str(invite.clinician_id))
    try:
        db.commit()
    except Exception:
        # Concurrent accept: UNIQUE constraint on ClinicianPatientLink fired.
        # Link already exists — treat as idempotent success.
        db.rollback()
        db.refresh(invite)
    else:
        db.refresh(invite)
    return invite_read(db, invite)


@router.post("/invites/{invite_id}/revoke", response_model=schemas.ClinicianInviteRead)
def revoke_clinician_invite(
    invite_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.patient.value)
    invite = db.query(models.ClinicianPatientInvite).filter(
        models.ClinicianPatientInvite.id == invite_id,
        models.ClinicianPatientInvite.patient_id == user.id,
    ).first()
    if invite is None:
        raise HTTPException(status_code=404, detail="Convite não encontrado")

    invite.status = models.InviteStatus.revoked.value
    invite.decided_at = utcnow()

    link = db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.clinician_id == invite.clinician_id,
        models.ClinicianPatientLink.patient_id == user.id,
    ).first()
    if link is not None:
        db.delete(link)

    audit(db, user, "revoke_clinician_access", "user", str(invite.clinician_id))
    db.commit()
    db.refresh(invite)
    return invite_read(db, invite)
