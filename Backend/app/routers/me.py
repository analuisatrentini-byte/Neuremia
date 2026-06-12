"""/me/* — endpoints scoped to the authenticated patient."""
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user, require_role
from ..services import (
    alert_read,
    assessment_read,
    audit,
    checkin_read,
    invite_read,
    report_read,
    user_read,
)


router = APIRouter(prefix="/me", tags=["me"])


@router.get("", response_model=schemas.UserRead)
def me(user: models.User = Depends(current_user)):
    return user


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
def export_my_account(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    checkins = (
        db.query(models.DailyCheckIn)
        .filter(models.DailyCheckIn.patient_id == user.id)
        .order_by(models.DailyCheckIn.created_at.desc())
        .all()
    )
    assessments = (
        db.query(models.ScaleAssessment)
        .filter(models.ScaleAssessment.patient_id == user.id)
        .order_by(models.ScaleAssessment.created_at.desc())
        .all()
    )
    alerts = (
        db.query(models.ClinicalAlert)
        .filter(models.ClinicalAlert.patient_id == user.id)
        .order_by(models.ClinicalAlert.created_at.desc())
        .all()
    )
    reports = (
        db.query(models.ClinicalReport)
        .filter(models.ClinicalReport.patient_id == user.id)
        .order_by(models.ClinicalReport.created_at.desc())
        .all()
    )
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
    cutoff = datetime.utcnow() - timedelta(days=max(days_older_than, 1))
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
                clinician_full_name=clinician.full_name,
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
        invite.decided_at = datetime.utcnow()

    audit(db, user, "revoke_clinician_access", "user", str(clinician_id))
    db.commit()
    return schemas.MessageResponse(message="Acesso do médico removido.")


@router.get("/invites", response_model=list[schemas.ClinicianInviteRead])
def list_my_invites(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    require_role(user, models.UserRole.patient.value)
    invites = (
        db.query(models.ClinicianPatientInvite)
        .filter(
            models.ClinicianPatientInvite.patient_id == user.id,
            models.ClinicianPatientInvite.status == models.InviteStatus.pending.value,
        )
        .order_by(models.ClinicianPatientInvite.created_at.desc())
        .all()
    )
    return [invite_read(db, invite) for invite in invites]


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
        raise HTTPException(status_code=404, detail="Invite not found")

    invite.status = models.InviteStatus.accepted.value
    invite.decided_at = datetime.utcnow()

    existing_link = db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.clinician_id == invite.clinician_id,
        models.ClinicianPatientLink.patient_id == user.id,
    ).first()
    if existing_link is None:
        db.add(models.ClinicianPatientLink(
            clinician_id=invite.clinician_id, patient_id=user.id
        ))

    audit(db, user, "accept_clinician_invite", "user", str(invite.clinician_id))
    db.commit()
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
        raise HTTPException(status_code=404, detail="Invite not found")

    invite.status = models.InviteStatus.revoked.value
    invite.decided_at = datetime.utcnow()

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
