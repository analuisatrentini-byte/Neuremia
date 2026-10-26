"""/checkins, /assessments, /reports — patient-side write endpoints, plus the
clinical-alert fan-out that high-risk submissions trigger."""
import json
import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from .. import models, schemas

logger = logging.getLogger("neuremia.checkins")
from ..baselines import recompute_for_patient as recompute_baselines
from ..database import get_db
from ..dependencies import current_user, require_role
from ..episode_pipeline import EpisodeAlertEvent, detect_episode_events
from ..interventions import compute_pending_outcomes
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
    notify_linked_clinicians_report,
    report_read,
    route_clinical_alert_notification,
    update_risk_cache,
)


router = APIRouter(tags=["clinical"])


def _clinical_alert(
    patient_id: int,
    level: str,
    alert_type: models.AlertType,
    escalation_target: models.EscalationTarget,
    title: str,
    message: str,
) -> models.ClinicalAlert:
    return models.ClinicalAlert(
        patient_id=patient_id,
        level=level,
        alert_type=alert_type.value,
        escalation_target=escalation_target.value,
        title=title,
        message=encrypt_field(message),
    )


def _recent_checkins(
    db: Session,
    patient_id: int,
    limit: int = 90,
) -> list[models.DailyCheckIn]:
    return (
        db.query(models.DailyCheckIn)
        .filter(
            models.DailyCheckIn.patient_id == patient_id,
            models.DailyCheckIn.deleted_at.is_(None),
        )
        .order_by(models.DailyCheckIn.created_at.desc())
        .limit(limit)
        .all()
    )


def _recent_assessments(db: Session, patient_id: int, limit: int = 12) -> list[models.ScaleAssessment]:
    return (
        db.query(models.ScaleAssessment)
        .filter(
            models.ScaleAssessment.patient_id == patient_id,
            models.ScaleAssessment.deleted_at.is_(None),
        )
        .order_by(models.ScaleAssessment.created_at.desc())
        .limit(limit)
        .all()
    )


def _recent_alert_keys(db: Session, patient_id: int) -> set[str]:
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(hours=20)
    recent_alerts = (
        db.query(models.ClinicalAlert)
        .filter(
            models.ClinicalAlert.patient_id == patient_id,
            models.ClinicalAlert.deleted_at.is_(None),
            models.ClinicalAlert.created_at >= cutoff,
        )
        .all()
    )
    return {f"{alert.alert_type}:{alert.title}" for alert in recent_alerts}


def _episode_events_to_create(
    db: Session,
    patient_id: int,
    payload: schemas.DailyCheckInCreate,
) -> list[EpisodeAlertEvent]:
    existing = _recent_alert_keys(db, patient_id)
    events = detect_episode_events(
        current=payload,
        previous=_recent_checkins(db, patient_id),
        assessments=_recent_assessments(db, patient_id),
    )
    return [
        event for event in events
        if f"{event.alert_type.value}:{event.title}" not in existing
    ]


def _detect_assessment_alert(
    payload: schemas.ScaleAssessmentCreate,
) -> tuple[str, models.AlertType, models.EscalationTarget, str, str] | None:
    if payload.scale_name == "YMRS" and payload.score >= 22:
        return (
            "high",
            models.AlertType.psychiatric_emergency,
            models.EscalationTarget.clinician_caregiver_now,
            "YMRS em faixa de mania aguda",
            "YMRS igual ou acima de 22 requer avaliação clínica imediata.",
        )
    if payload.scale_name == "PHQ-9" and payload.score >= 20:
        return (
            "moderate",
            models.AlertType.clinical_watch,
            models.EscalationTarget.clinician_digest,
            "PHQ-9 em faixa severa",
            "Nova escala em faixa severa deve entrar no acompanhamento clínico diário.",
        )
    if payload.scale_name == "GAD-7" and payload.score >= 15:
        return (
            "moderate",
            models.AlertType.clinical_watch,
            models.EscalationTarget.clinician_digest,
            "GAD-7 em faixa severa",
            "Nova escala em faixa severa deve entrar no acompanhamento clínico diário.",
        )
    return None


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

    alert_events = _episode_events_to_create(db, user.id, payload)
    for event in alert_events:
        db.add(_clinical_alert(
            user.id,
            event.level,
            event.alert_type,
            event.escalation_target,
            event.title,
            event.message,
        ))

    audit(db, user, "create_checkin", "daily_checkin", "pending")
    db.commit()
    db.refresh(checkin)

    # Notify AFTER commit so a notification failure never discards the check-in.
    for event in alert_events:
        try:
            route_clinical_alert_notification(
                db,
                user,
                event.alert_type.value,
                event.escalation_target.value,
                event.title,
                event.message,
            )
        except Exception as e:
            logger.warning("Failed to notify clinicians for checkin %s: %s", checkin.id, e)
            audit(db, user, "notification_failed", "daily_checkin", str(checkin.id))
            db.commit()

    # M9 — keep risk cache fresh after every check-in.
    update_risk_cache(db, user.id)

    # Recompute personal baselines (rolling 60d) and backfill intervention
    # outcomes that now have enough post-trigger check-ins to score. Both
    # run in the same transaction as the check-in insert so a failure here
    # never leaves the risk cache and the personalization layer out of sync.
    recompute_baselines(db, user.id)
    compute_pending_outcomes(db, user.id)
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
    alert_event = _detect_assessment_alert(payload)
    if alert_event is not None:
        level, alert_type, escalation_target, title, message = alert_event
        db.add(_clinical_alert(patient_id, level, alert_type, escalation_target, title, message))
    audit(db, user, "create_assessment", "scale_assessment", "pending")
    db.commit()
    db.refresh(assessment)
    if alert_event is not None:
        patient = db.query(models.User).filter(models.User.id == patient_id).first()
        if patient is not None:
            try:
                route_clinical_alert_notification(
                    db,
                    patient,
                    alert_type.value,
                    escalation_target.value,
                    title,
                    message,
                )
                db.commit()
            except Exception as e:
                logger.warning("Failed to route assessment alert %s: %s", assessment.id, e)
                audit(db, user, "notification_failed", "scale_assessment", str(assessment.id))
                db.commit()
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
                    "Neuremia",
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
