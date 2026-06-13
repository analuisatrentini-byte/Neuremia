"""/clinician/* — endpoints accessible only to users with role=clinician."""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

_INVITE_TTL_DAYS = 30

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user, require_role
from ..services import (
    audit,
    decrypted_full_name,
    invite_read,
    patient_risk_summary_batch,
    sent_invite_read_batch,
    user_read,
)


router = APIRouter(prefix="/clinician", tags=["clinician"])


@router.post("/invites", response_model=schemas.ClinicianInviteRead)
def create_clinician_invite(
    payload: schemas.ClinicianInviteCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    """Clinician requests access; link only created when patient accepts."""
    require_role(user, models.UserRole.clinician.value)
    patient = db.query(models.User).filter(
        models.User.email == payload.patient_email.lower(),
        models.User.role == models.UserRole.patient.value,
    ).first()
    if patient is None:
        raise HTTPException(status_code=404, detail="Patient not found")

    existing_link = db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.clinician_id == user.id,
        models.ClinicianPatientLink.patient_id == patient.id,
    ).first()
    if existing_link is not None:
        raise HTTPException(status_code=409, detail="Patient already linked")

    pending = db.query(models.ClinicianPatientInvite).filter(
        models.ClinicianPatientInvite.clinician_id == user.id,
        models.ClinicianPatientInvite.patient_id == patient.id,
        models.ClinicianPatientInvite.status == models.InviteStatus.pending.value,
    ).first()
    if pending is not None:
        invite = pending
    else:
        invite = models.ClinicianPatientInvite(
            clinician_id=user.id,
            patient_id=patient.id,
            expires_at=datetime.now(timezone.utc) + timedelta(days=_INVITE_TTL_DAYS),
        )
        db.add(invite)
        audit(db, user, "invite_patient", "user", str(patient.id))
        db.commit()
        db.refresh(invite)

    return schemas.ClinicianInviteRead(
        id=invite.id,
        clinician_id=invite.clinician_id,
        patient_id=invite.patient_id,
        clinician_full_name=decrypted_full_name(user),
        clinician_email=user.email,
        status=invite.status,
        created_at=invite.created_at,
    )


@router.get("/invites", response_model=list[schemas.ClinicianSentInviteRead])
def list_clinician_invites(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    require_role(user, models.UserRole.clinician.value)
    invites = (
        db.query(models.ClinicianPatientInvite)
        .filter(models.ClinicianPatientInvite.clinician_id == user.id)
        .order_by(models.ClinicianPatientInvite.created_at.desc())
        .all()
    )
    return sent_invite_read_batch(db, invites)


@router.post("/patients", response_model=schemas.UserRead, deprecated=True)
def link_patient_deprecated(
    payload: schemas.LinkPatientRequest,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    """Deprecated; routes through /clinician/invites."""
    require_role(user, models.UserRole.clinician.value)
    invite_response = create_clinician_invite(
        schemas.ClinicianInviteCreate(patient_email=payload.patient_email),
        db=db,
        user=user,
    )
    patient = db.query(models.User).filter(models.User.id == invite_response.patient_id).first()
    if patient is None:
        raise HTTPException(status_code=404, detail="Patient not found")
    return user_read(db, patient, include_risk=False)


@router.get("/patients", response_model=schemas.PatientListResponse)
def clinician_patients(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.clinician.value)
    links = db.query(models.ClinicianPatientLink).filter(
        models.ClinicianPatientLink.clinician_id == user.id
    ).all()
    patient_ids = [link.patient_id for link in links]
    total = len(patient_ids)
    if not patient_ids:
        return schemas.PatientListResponse(items=[], total=0, skip=skip, limit=limit)
    patients = db.query(models.User).filter(models.User.id.in_(patient_ids)).all()
    risk_by_patient = patient_risk_summary_batch(db, patient_ids)
    ranked_patients = []
    for patient in patients:
        score, level = risk_by_patient.get(patient.id, (None, None))
        ranked_patients.append(
            schemas.UserRead(
                id=patient.id,
                email=patient.email,
                full_name=decrypted_full_name(patient),
                role=patient.role,
                created_at=patient.created_at,
                risk_score=score,
                risk_level=level,
            )
        )
    ranked_patients.sort(key=lambda p: p.risk_score or -1, reverse=True)
    page = ranked_patients[skip: skip + limit]
    return schemas.PatientListResponse(items=page, total=total, skip=skip, limit=limit)
