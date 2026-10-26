"""/devices/push-token — register/delete an APNs/FCM device token for the user."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user
from ..services import audit


router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("/push-token", response_model=schemas.DeviceTokenRead)
def register_push_token(
    payload: schemas.DeviceTokenCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    token = db.query(models.DeviceToken).filter(
        models.DeviceToken.user_id == user.id,
        models.DeviceToken.token == payload.token,
    ).first()
    if token is None:
        token = models.DeviceToken(
            user_id=user.id, token=payload.token, platform=payload.platform
        )
        db.add(token)
        audit(db, user, "register_push_token", "device_token", "pending")
    else:
        token.platform = payload.platform
        audit(db, user, "refresh_push_token", "device_token", str(token.id))

    db.commit()
    db.refresh(token)
    return token


@router.delete("/push-token/{token_id}", response_model=schemas.MessageResponse)
def delete_push_token(
    token_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    """Delete a registered push token to prevent orphaned device tokens."""
    token = db.query(models.DeviceToken).filter(
        models.DeviceToken.id == token_id,
        models.DeviceToken.user_id == user.id,
    ).first()
    if token is None:
        raise HTTPException(status_code=404, detail="Token nao encontrado")
    db.delete(token)
    audit(db, user, "delete_push_token", "device_token", str(token_id))
    db.commit()
    return schemas.MessageResponse(message="Token removido com sucesso.")
