"""/devices/push-token — register an APNs/FCM device token for the user."""
from fastapi import APIRouter, Depends
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
