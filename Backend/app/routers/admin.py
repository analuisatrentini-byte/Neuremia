"""/admin/* endpoints — protected by the admin API key header.

Use only by backend operators. Surfaces:
- session revocation (Sprint 15)
- token-table cleanup (Sprint 10/14)
- role promotion (Sprint 1)
"""
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import require_admin


router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])


@router.post("/refresh-tokens/purge", response_model=schemas.AdminPurgeResponse)
def admin_purge_refresh_tokens(db: Session = Depends(get_db)):
    """Reaps short-lived auth records that no longer matter."""
    now = datetime.utcnow()
    refresh_cutoff = now - timedelta(days=1)

    purged_refresh = (
        db.query(models.RefreshToken)
        .filter(
            (models.RefreshToken.expires_at < now)
            | (models.RefreshToken.revoked_at.isnot(None) & (models.RefreshToken.revoked_at < refresh_cutoff))
        )
        .delete(synchronize_session=False)
    )

    purged_jtis = (
        db.query(models.RevokedAccessToken)
        .filter(models.RevokedAccessToken.expires_at < now)
        .delete(synchronize_session=False)
    )

    purged_resets = (
        db.query(models.PasswordResetToken)
        .filter(
            (models.PasswordResetToken.expires_at < now)
            | (models.PasswordResetToken.used_at.isnot(None))
        )
        .delete(synchronize_session=False)
    )

    db.commit()
    return schemas.AdminPurgeResponse(
        deleted_refresh_tokens=purged_refresh,
        deleted_access_token_jtis=purged_jtis,
        deleted_password_reset_tokens=purged_resets,
    )


@router.post("/users/{user_id}/revoke-sessions", response_model=schemas.AdminRevokeSessionsResponse)
def admin_revoke_sessions(user_id: int, db: Session = Depends(get_db)):
    """Cuts every still-valid token for the target user (Sprint 15)."""
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    user.token_epoch = user.token_epoch + 1
    now = datetime.utcnow()
    revoked_refresh = (
        db.query(models.RefreshToken)
        .filter(
            models.RefreshToken.user_id == user.id,
            models.RefreshToken.revoked_at.is_(None),
        )
        .update({models.RefreshToken.revoked_at: now}, synchronize_session=False)
    )

    db.add(models.AuditLog(
        actor_user_id=user.id,
        action="admin_revoke_sessions",
        resource_type="user",
        resource_id=str(user_id),
    ))
    db.commit()
    db.refresh(user)
    return schemas.AdminRevokeSessionsResponse(
        user_id=user.id,
        new_token_epoch=user.token_epoch,
        revoked_refresh_tokens=revoked_refresh,
    )


@router.post("/users/{user_id}/role", response_model=schemas.UserRead)
def admin_set_role(user_id: int, payload: schemas.AdminPromoteRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    user.role = payload.role
    db.add(models.AuditLog(
        actor_user_id=user.id,
        action="admin_set_role",
        resource_type="user",
        resource_id=f"{user_id}->{payload.role}",
    ))
    db.commit()
    db.refresh(user)
    return schemas.UserRead(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        created_at=user.created_at,
        risk_score=None,
        risk_level=None,
    )
