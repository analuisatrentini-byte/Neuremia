"""/patients/{patient_id}/* — clinician-side read endpoints for a specific
patient. Authorization is enforced via `can_access_patient` (Sprint 1)."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user
from ..services import (
    alert_read,
    assessment_read,
    audit,
    can_access_patient,
    checkin_read,
    report_read,
)


router = APIRouter(prefix="/patients", tags=["patients"])


def _ensure_access(db: Session, user: models.User, patient_id: int) -> None:
    if not can_access_patient(db, user, patient_id):
        raise HTTPException(status_code=403, detail="No access to patient")


@router.get("/{patient_id}/checkins", response_model=list[schemas.DailyCheckInRead])
def patient_checkins(
    patient_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    _ensure_access(db, user, patient_id)
    # N-M3: log every clinician read of PHI (LGPD Art. 37 — access trail)
    audit(db, user, "read_patient_checkins", "daily_checkin", str(patient_id))
    checkins = (
        db.query(models.DailyCheckIn)
        .filter(
            models.DailyCheckIn.patient_id == patient_id,
            models.DailyCheckIn.deleted_at.is_(None),
        )
        .order_by(models.DailyCheckIn.created_at.desc())
        .all()
    )
    db.commit()
    return [checkin_read(item) for item in checkins]


@router.get("/{patient_id}/assessments", response_model=list[schemas.ScaleAssessmentRead])
def patient_assessments(
    patient_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    _ensure_access(db, user, patient_id)
    audit(db, user, "read_patient_assessments", "scale_assessment", str(patient_id))
    assessments = (
        db.query(models.ScaleAssessment)
        .filter(models.ScaleAssessment.patient_id == patient_id)
        .order_by(models.ScaleAssessment.created_at.desc())
        .all()
    )
    db.commit()
    return [assessment_read(item) for item in assessments]


@router.get("/{patient_id}/alerts", response_model=list[schemas.ClinicalAlertRead])
def patient_alerts(
    patient_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    _ensure_access(db, user, patient_id)
    audit(db, user, "read_patient_alerts", "clinical_alert", str(patient_id))
    alerts = (
        db.query(models.ClinicalAlert)
        .filter(
            models.ClinicalAlert.patient_id == patient_id,
            models.ClinicalAlert.deleted_at.is_(None),
        )
        .order_by(models.ClinicalAlert.created_at.desc())
        .all()
    )
    db.commit()
    return [alert_read(alert) for alert in alerts]


@router.get("/{patient_id}/reports", response_model=list[schemas.ClinicalReportRead])
def patient_reports(
    patient_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    _ensure_access(db, user, patient_id)
    audit(db, user, "read_patient_reports", "clinical_report", str(patient_id))
    reports = (
        db.query(models.ClinicalReport)
        .filter(
            models.ClinicalReport.patient_id == patient_id,
            models.ClinicalReport.deleted_at.is_(None),
        )
        .order_by(models.ClinicalReport.created_at.desc())
        .all()
    )
    db.commit()
    return [report_read(report) for report in reports]


# Sprint B: o iOS marca alertas como acknowledged localmente (linha ~10781 do
# ContentView.swift), mas o backend não tinha endpoint para sincronizar isso.
# Resultado: risk score acumulado nunca diminuía no servidor, a triagem
# clínica via `/clinician/patients` ficava poluída com alertas antigos.
@router.post(
    "/{patient_id}/alerts/{alert_id}/acknowledge",
    response_model=schemas.ClinicalAlertRead,
)
def acknowledge_alert(
    patient_id: int,
    alert_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    _ensure_access(db, user, patient_id)
    alert = (
        db.query(models.ClinicalAlert)
        .filter(
            models.ClinicalAlert.id == alert_id,
            models.ClinicalAlert.patient_id == patient_id,
        )
        .first()
    )
    if alert is None:
        raise HTTPException(status_code=404, detail="Alert not found")

    # Idempotente: ack 2× não causa erro, só audita uma vez.
    if not alert.acknowledged:
        alert.acknowledged = True
        audit(db, user, "acknowledge_alert", "clinical_alert", str(alert.id))
        db.commit()
        db.refresh(alert)
    return alert_read(alert)
