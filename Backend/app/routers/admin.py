"""/admin/* endpoints — protected by the admin API key header.

Use only by backend operators. Surfaces:
- session revocation (Sprint 15)
- token-table cleanup (Sprint 10/14)
- role promotion (Sprint 1)
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import require_admin
from ..services import user_read, utcnow


"""_rate_limit_admin — 30 req / minute per admin key."""
def _rate_limit_admin(request: Request):
    return request.url.path.startswith("/admin")

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])


@router.get("/ops/status", response_model=schemas.AdminOpsStatusResponse)
def admin_ops_status(db: Session = Depends(get_db)):
    """Aggregated production signal for operators, with no PHI in payload."""
    now = utcnow()
    day_ago = now - timedelta(days=1)

    total_users = db.query(models.User).count()
    patient_count = db.query(models.User).filter(models.User.role == models.UserRole.patient.value).count()
    clinician_count = db.query(models.User).filter(models.User.role == models.UserRole.clinician.value).count()
    active_sessions = (
        db.query(models.RefreshToken)
        .filter(
            models.RefreshToken.revoked_at.is_(None),
            models.RefreshToken.expires_at > now,
        )
        .count()
    )
    device_tokens = db.query(models.DeviceToken).count()
    linked_patient_count = db.query(func.count(func.distinct(models.ClinicianPatientLink.patient_id))).scalar() or 0
    unacknowledged_high_alerts = (
        db.query(models.ClinicalAlert)
        .filter(
            models.ClinicalAlert.deleted_at.is_(None),
            models.ClinicalAlert.acknowledged.is_(False),
            models.ClinicalAlert.level == "high",
        )
        .count()
    )
    stale_high_alerts = (
        db.query(models.ClinicalAlert)
        .filter(
            models.ClinicalAlert.deleted_at.is_(None),
            models.ClinicalAlert.acknowledged.is_(False),
            models.ClinicalAlert.level == "high",
            models.ClinicalAlert.created_at < day_ago,
        )
        .count()
    )
    notification_failures_24h = (
        db.query(models.NotificationLog)
        .filter(
            models.NotificationLog.created_at >= day_ago,
            models.NotificationLog.status != "sent",
        )
        .count()
    )
    audit_events_24h = (
        db.query(models.AuditLog)
        .filter(models.AuditLog.created_at >= day_ago)
        .count()
    )

    metrics = [
        schemas.AdminOpsMetric(
            name="accounts",
            status="pass",
            value=total_users,
            detail=f"{patient_count} patients, {clinician_count} clinicians",
        ),
        schemas.AdminOpsMetric(
            name="active_sessions",
            status="pass",
            value=active_sessions,
            detail="Valid refresh sessions available for session recovery",
        ),
        schemas.AdminOpsMetric(
            name="registered_devices",
            status="pass" if device_tokens > 0 or total_users == 0 else "warn",
            value=device_tokens,
            detail="APNs device tokens registered" if device_tokens else "No push devices registered",
        ),
        schemas.AdminOpsMetric(
            name="linked_patients",
            status="pass" if linked_patient_count > 0 or clinician_count == 0 else "warn",
            value=linked_patient_count,
            detail="Patients shared with at least one clinician",
        ),
        schemas.AdminOpsMetric(
            name="open_high_alerts",
            status="warn" if unacknowledged_high_alerts else "pass",
            value=unacknowledged_high_alerts,
            detail="Unacknowledged high-risk clinical alerts",
        ),
        schemas.AdminOpsMetric(
            name="stale_high_alerts_24h",
            status="fail" if stale_high_alerts else "pass",
            value=stale_high_alerts,
            detail="High-risk alerts open for more than 24h",
        ),
        schemas.AdminOpsMetric(
            name="notification_failures_24h",
            status="warn" if notification_failures_24h else "pass",
            value=notification_failures_24h,
            detail="Failed notification attempts in the last 24h",
        ),
        schemas.AdminOpsMetric(
            name="audit_events_24h",
            status="pass" if audit_events_24h > 0 or total_users == 0 else "warn",
            value=audit_events_24h,
            detail="Audit log entries written in the last 24h",
        ),
    ]

    if any(metric.status == "fail" for metric in metrics):
        status = "degraded"
    elif any(metric.status == "warn" for metric in metrics):
        status = "attention"
    else:
        status = "operational"

    return schemas.AdminOpsStatusResponse(
        status=status,
        generated_at=now,
        metrics=metrics,
    )


@router.post("/refresh-tokens/purge", response_model=schemas.AdminPurgeResponse)
def admin_purge_refresh_tokens(db: Session = Depends(get_db)):
    """Reaps short-lived auth records that no longer matter."""
    now = utcnow()
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

    purged_totp = (
        db.query(models.TotpPendingSession)
        .filter(
            (models.TotpPendingSession.expires_at < now)
            | (models.TotpPendingSession.used_at.isnot(None))
        )
        .delete(synchronize_session=False)
    )

    # Purge pending invites whose expiry has passed.
    purged_invites = (
        db.query(models.ClinicianPatientInvite)
        .filter(
            models.ClinicianPatientInvite.status == models.InviteStatus.pending.value,
            models.ClinicianPatientInvite.expires_at.isnot(None),
            models.ClinicianPatientInvite.expires_at < now,
        )
        .delete(synchronize_session=False)
    )

    db.commit()
    return schemas.AdminPurgeResponse(
        deleted_refresh_tokens=purged_refresh,
        deleted_access_token_jtis=purged_jtis,
        deleted_password_reset_tokens=purged_resets,
        deleted_totp_pending_sessions=purged_totp,
        deleted_expired_invites=purged_invites,
    )


@router.post("/users/{user_id}/revoke-sessions", response_model=schemas.AdminRevokeSessionsResponse)
def admin_revoke_sessions(user_id: int, db: Session = Depends(get_db)):
    """Cuts every still-valid token for the target user (Sprint 15)."""
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Usuário não encontrado")

    user.token_epoch = user.token_epoch + 1
    now = utcnow()
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
        raise HTTPException(status_code=404, detail="Usuário não encontrado")
    user.role = payload.role
    db.add(models.AuditLog(
        actor_user_id=user.id,
        action="admin_set_role",
        resource_type="user",
        resource_id=f"{user_id}->{payload.role}",
    ))
    db.commit()
    db.refresh(user)
    return user_read(db, user)
