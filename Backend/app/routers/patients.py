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
    checkins = (
        db.query(models.DailyCheckIn)
        .filter(models.DailyCheckIn.patient_id == patient_id)
        .order_by(models.DailyCheckIn.created_at.desc())
        .all()
    )
    return [checkin_read(item) for item in checkins]


@router.get("/{patient_id}/assessments", response_model=list[schemas.ScaleAssessmentRead])
def patient_assessments(
    patient_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    _ensure_access(db, user, patient_id)
    assessments = (
        db.query(models.ScaleAssessment)
        .filter(models.ScaleAssessment.patient_id == patient_id)
        .order_by(models.ScaleAssessment.created_at.desc())
        .all()
    )
    return [assessment_read(item) for item in assessments]


@router.get("/{patient_id}/alerts", response_model=list[schemas.ClinicalAlertRead])
def patient_alerts(
    patient_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    _ensure_access(db, user, patient_id)
    alerts = (
        db.query(models.ClinicalAlert)
        .filter(models.ClinicalAlert.patient_id == patient_id)
        .order_by(models.ClinicalAlert.created_at.desc())
        .all()
    )
    return [alert_read(alert) for alert in alerts]


@router.get("/{patient_id}/reports", response_model=list[schemas.ClinicalReportRead])
def patient_reports(
    patient_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    _ensure_access(db, user, patient_id)
    reports = (
        db.query(models.ClinicalReport)
        .filter(models.ClinicalReport.patient_id == patient_id)
        .order_by(models.ClinicalReport.created_at.desc())
        .all()
    )
    return [report_read(report) for report in reports]
