"""/checkins, /assessments, /reports — patient-side write endpoints, plus the
clinical-alert fan-out that high-risk submissions trigger."""
import json

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user, require_role
from ..notifications import notifications
from ..rate_limit import limiter
from ..security import encrypt_field
from ..services import (
    alert_read,
    assessment_read,
    audit,
    can_access_patient,
    checkin_read,
    decrypted_full_name,
    has_active_consent,
    log_notification,
    notify_linked_clinicians,
    notify_linked_clinicians_report,
    report_read,
    update_risk_cache,
)


router = APIRouter(tags=["clinical"])


@router.post("/checkins", response_model=schemas.DailyCheckInRead)
@limiter.limit("30/minute")
def create_checkin(
    request: Request,
    payload: schemas.DailyCheckInCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.patient.value)
    if not has_active_consent(db, user.id, "clinical_data_storage"):
        raise HTTPException(status_code=403, detail="Consentimento LGPD para armazenamento clínico não concedido")
    payload_data = payload.model_dump()
    payload_data["side_effects"] = encrypt_field(payload.side_effects)
    payload_data["automatic_thoughts"] = encrypt_field(payload.automatic_thoughts)
    payload_data["journal_entry"] = encrypt_field(payload.journal_entry)
    checkin = models.DailyCheckIn(patient_id=user.id, **payload_data)
    db.add(checkin)

    if payload.suicidal_ideation or payload.mood <= 1 or payload.anxiety >= 4.5:
        title = "Risco clínico prioritário"
        message = "Triagem ou sintomas recentes indicam necessidade de revisão clínica prioritária."
        db.add(models.ClinicalAlert(
            patient_id=user.id,
            level="high",
            title=title,
            message=encrypt_field(message),
        ))
        notify_linked_clinicians(db, user, title, message)

    audit(db, user, "create_checkin", "daily_checkin", "pending")
    db.commit()
    db.refresh(checkin)
    # M9 — keep risk cache fresh after every check-in.
    update_risk_cache(db, user.id)
    db.commit()
    return checkin_read(checkin)


@router.post("/assessments", response_model=schemas.ScaleAssessmentRead)
@limiter.limit("10/minute")
def create_assessment(
    request: Request,
    payload: schemas.ScaleAssessmentCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    patient_id = user.id if user.role == models.UserRole.patient.value else payload.patient_id
    if patient_id is None or not can_access_patient(db, user, patient_id):
        raise HTTPException(status_code=403, detail="Acesso negado ao paciente")
    if not has_active_consent(db, patient_id, "clinical_data_storage"):
        raise HTTPException(status_code=403, detail="Consentimento LGPD para armazenamento clínico não concedido")

    assessment = models.ScaleAssessment(
        patient_id=patient_id,
        scale_name=payload.scale_name,
        answers_json=json.dumps(payload.answers),
        score=payload.score,
        interpretation=payload.interpretation,
    )
    db.add(assessment)
    audit(db, user, "create_assessment", "scale_assessment", "pending")
    db.commit()
    db.refresh(assessment)
    return assessment_read(assessment)


@router.post("/reports", response_model=schemas.ClinicalReportRead)
@limiter.limit("10/minute")
def create_report(
    request: Request,
    payload: schemas.ClinicalReportCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    patient_id = user.id if user.role == models.UserRole.patient.value else payload.patient_id
    if patient_id is None or not can_access_patient(db, user, patient_id):
        raise HTTPException(status_code=403, detail="Acesso negado ao paciente")
    if not has_active_consent(db, patient_id, "clinical_data_storage"):
        raise HTTPException(status_code=403, detail="Consentimento LGPD para armazenamento clínico não concedido")

    report = models.ClinicalReport(
        patient_id=patient_id,
        risk_level=payload.risk_level,
        summary=encrypt_field(payload.summary),
    )
    db.add(report)
    audit(db, user, "create_report", "clinical_report", "pending")
    patient = db.query(models.User).filter(models.User.id == patient_id).first()
    if payload.auto_send and patient is not None:
        notify_linked_clinicians_report(db, patient, payload.summary)
        if payload.care_team_contact:
            # Sprint B: patient.full_name é ciphertext; SMTP body já é redacted
            # mas passamos decrypted pra manter API estável.
            patient_display_name = decrypted_full_name(patient)
            try:
                sent = notifications.send_clinical_report_email(
                    payload.care_team_contact, patient_display_name, payload.summary
                )
                log_notification(
                    db, patient_id, payload.care_team_contact,
                    "email", "manual_care_team_report", sent, "manual_contact",
                )
            except Exception:
                log_notification(
                    db, patient_id, payload.care_team_contact,
                    "email", "manual_care_team_report", False, "exception",
                )
                audit(db, user, "care_team_email_failed", "clinical_report", "pending")
        if payload.apns_token:
            try:
                sent = notifications.send_push_webhook(
                    payload.apns_token,
                    "NeuroFlow",
                    "Relatório enviado ao time de cuidado",
                    data={"event_type": "clinical_report", "patient_id": str(patient_id)},
                )
                log_notification(
                    db, patient_id, "manual_apns_token",
                    "push", "manual_care_team_report", sent, "manual_token",
                )
            except Exception:
                log_notification(
                    db, patient_id, "manual_apns_token",
                    "push", "manual_care_team_report", False, "exception",
                )
                audit(db, user, "push_webhook_failed", "clinical_report", "pending")
    db.commit()
    db.refresh(report)
    return report_read(report)


@router.delete("/checkins/{checkin_id}", response_model=schemas.MessageResponse)
def delete_checkin(
    checkin_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.patient.value)
    checkin = (
        db.query(models.DailyCheckIn)
        .filter(
            models.DailyCheckIn.id == checkin_id,
            models.DailyCheckIn.patient_id == user.id,
            models.DailyCheckIn.deleted_at.is_(None),
        )
        .first()
    )
    if checkin is None:
        raise HTTPException(status_code=404, detail="Check-in não encontrado")
    checkin.deleted_at = datetime.now(timezone.utc)
    audit(db, user, "delete_checkin", "daily_checkin", str(checkin_id))
    db.commit()
    update_risk_cache(db, user.id)
    db.commit()
    return schemas.MessageResponse(message="Check-in removido.")
