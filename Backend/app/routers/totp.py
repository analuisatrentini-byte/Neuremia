"""M2 — TOTP-based 2FA endpoints.

Flow for users who enable 2FA:
  1. POST /auth/2fa/setup      → get secret + provisioning URI (QR code)
  2. POST /auth/2fa/enable     → confirm code; sets totp_enabled=True
  3. Login flow: /auth/login returns {requires_totp:true, pending_session_id}
     when password is correct but TOTP is still required.
  4. POST /auth/2fa/verify     → exchange (pending_session_id + code) for
     a full TokenResponse.
  5. POST /auth/2fa/disable    → verify live code + disable TOTP.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user
from ..security import (
    decrypt_field,
    encrypt_field,
    generate_totp_pending_session,
    generate_totp_secret,
    hash_pending_session,
    totp_provisioning_uri,
    verify_totp_code,
)
from ..services import audit, issue_token_pair, user_read, utcnow


router = APIRouter(prefix="/auth/2fa", tags=["2fa"])


@router.post("/setup", response_model=schemas.TotpSetupResponse)
def totp_setup(
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    """Generate a new TOTP secret for the user. Does NOT enable 2FA yet — the
    client must confirm with a live code via /auth/2fa/enable."""
    secret = generate_totp_secret()
    user.totp_secret_enc = encrypt_field(secret)
    # totp_enabled stays False until /enable confirms the code.
    db.commit()
    return schemas.TotpSetupResponse(
        secret=secret,
        provisioning_uri=totp_provisioning_uri(secret, user.email),
    )


@router.post("/enable", response_model=schemas.MessageResponse)
def totp_enable(
    payload: schemas.TotpConfirmRequest,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    """Verify that the authenticator app is configured correctly, then enable 2FA."""
    if not user.totp_secret_enc:
        raise HTTPException(status_code=400, detail="Configure o 2FA em /auth/2fa/setup primeiro")
    secret = decrypt_field(user.totp_secret_enc)
    if not verify_totp_code(secret, payload.code):
        raise HTTPException(status_code=400, detail="Código TOTP inválido")
    user.totp_enabled = True
    audit(db, user, "2fa_enabled", "user", str(user.id))
    db.commit()
    return schemas.MessageResponse(message="2FA ativado.")


@router.post("/disable", response_model=schemas.MessageResponse)
def totp_disable(
    payload: schemas.TotpConfirmRequest,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    """Verify a live TOTP code then disable 2FA and wipe the secret."""
    if not user.totp_enabled or not user.totp_secret_enc:
        raise HTTPException(status_code=400, detail="2FA nao esta ativo")
    secret = decrypt_field(user.totp_secret_enc)
    if not verify_totp_code(secret, payload.code):
        raise HTTPException(status_code=400, detail="Código TOTP inválido")
    user.totp_enabled = False
    user.totp_secret_enc = None
    audit(db, user, "2fa_disabled", "user", str(user.id))
    db.commit()
    return schemas.MessageResponse(message="2FA desativado.")


@router.post("/verify", response_model=schemas.TokenResponse)
def totp_verify(
    payload: schemas.TotpVerifyRequest,
    db: Session = Depends(get_db),
):
    """Exchange a pending_session_id + TOTP code for a real TokenResponse.
    Called by the client after /auth/login returns requires_totp=True."""
    digest = hash_pending_session(payload.pending_session_id)
    session = db.query(models.TotpPendingSession).filter(
        models.TotpPendingSession.session_hash == digest,
    ).first()

    invalid = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Session invalida ou expirada",
    )
    if session is None or session.used_at is not None:
        raise invalid
    if session.expires_at < utcnow():
        raise invalid

    user = db.query(models.User).filter(models.User.id == session.user_id).first()
    if user is None or not user.totp_enabled or not user.totp_secret_enc:
        raise invalid

    secret = decrypt_field(user.totp_secret_enc)
    if not verify_totp_code(secret, payload.code):
        raise HTTPException(status_code=400, detail="Codigo TOTP invalido")

    session.used_at = utcnow()
    access, refresh = issue_token_pair(db, user)
    audit(db, user, "2fa_login", "user", str(user.id))
    db.commit()
    return schemas.TokenResponse(
        access_token=access,
        refresh_token=refresh,
        user=user_read(db, user),
    )
