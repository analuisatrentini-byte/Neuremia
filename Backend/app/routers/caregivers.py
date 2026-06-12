"""/caregivers — CRUD endpoints the patient uses to manage trusted contacts."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user, require_role
from ..services import audit


router = APIRouter(prefix="/caregivers", tags=["caregivers"])


@router.get("", response_model=list[schemas.CaregiverContactRead])
def caregivers(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    require_role(user, models.UserRole.patient.value)
    return (
        db.query(models.CaregiverContact)
        .filter(models.CaregiverContact.patient_id == user.id)
        .order_by(models.CaregiverContact.created_at.desc())
        .all()
    )


@router.post("", response_model=schemas.CaregiverContactRead)
def create_caregiver(
    payload: schemas.CaregiverContactCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.patient.value)
    caregiver = models.CaregiverContact(
        patient_id=user.id,
        name=payload.name,
        contact=payload.contact,
        relationship=payload.relationship,
        share_enabled=payload.share_enabled,
    )
    db.add(caregiver)
    audit(db, user, "create_caregiver", "caregiver_contact", "pending")
    db.commit()
    db.refresh(caregiver)
    return caregiver


@router.patch("/{caregiver_id}", response_model=schemas.CaregiverContactRead)
def update_caregiver(
    caregiver_id: int,
    payload: schemas.CaregiverContactCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.patient.value)
    caregiver = db.query(models.CaregiverContact).filter(
        models.CaregiverContact.id == caregiver_id,
        models.CaregiverContact.patient_id == user.id,
    ).first()
    if caregiver is None:
        raise HTTPException(status_code=404, detail="Caregiver not found")

    caregiver.name = payload.name
    caregiver.contact = payload.contact
    caregiver.relationship = payload.relationship
    caregiver.share_enabled = payload.share_enabled
    audit(db, user, "update_caregiver", "caregiver_contact", str(caregiver.id))
    db.commit()
    db.refresh(caregiver)
    return caregiver


@router.delete("/{caregiver_id}", response_model=schemas.MessageResponse)
def delete_caregiver(
    caregiver_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    require_role(user, models.UserRole.patient.value)
    caregiver = db.query(models.CaregiverContact).filter(
        models.CaregiverContact.id == caregiver_id,
        models.CaregiverContact.patient_id == user.id,
    ).first()
    if caregiver is None:
        raise HTTPException(status_code=404, detail="Caregiver not found")

    db.delete(caregiver)
    audit(db, user, "delete_caregiver", "caregiver_contact", str(caregiver_id))
    db.commit()
    return schemas.MessageResponse(message="Cuidador removido.")
