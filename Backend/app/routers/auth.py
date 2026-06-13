"""/auth/* endpoints: register, login, refresh, logout, password reset.

Extracted from the monolithic main.py in Sprint 17 (C32). All requests in
this router are throttled by `slowapi`; disabled in tests via env.
"""
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..dependencies import current_user, oauth2_scheme
from ..notifications import notifications
from ..rate_limit import limiter
from ..security import (
    decode_access_token_payload,
    encrypt_field,
    generate_totp_pending_session,
    hash_password,
    hash_refresh_token,
    hash_reset_code,
    verify_password,
)
from ..services import audit, issue_token_pair, user_read, utcnow


router = APIRouter(prefix="/auth", tags=["auth"])


_REGISTER_GENERIC = "Se este e-mail estiver disponivel, voce receberá um e-mail de confirmacao."


@router.post("/register")
@limiter.limit("5/minute")
def register(
    request: Request,
    payload: schemas.UserCreate,
    db: Session = Depends(get_db),
):
    existing = db.query(models.User).filter(models.User.email == payload.email.lower()).first()
    if existing is not None:
        # Return 200 with neutral message — identical status to a real registration
        # so an attacker cannot enumerate registered patients by trying email addresses.
        return JSONResponse(status_code=200, content={"message": _REGISTER_GENERIC})

    # Sprint B / LGPD: full_name encriptado at rest. Response devolve plaintext
    # via `user_read` (que decripta).
    user = models.User(
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
        role=models.UserRole.patient.value,
        full_name=encrypt_field(payload.full_name),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    audit(db, user, "register", "user", str(user.id))
    access, refresh = issue_token_pair(db, user)
    db.commit()
    return schemas.TokenResponse(
        access_token=access,
        refresh_token=refresh,
        user=user_read(db, user),
    )


# Sprint B: bloqueio progressivo. Threshold conservador para evitar lockout
# acidental, escalada de backoff geométrica.
_FAILED_LOGIN_THRESHOLD = 5
_FAILED_LOGIN_BACKOFF_BASE_SECONDS = 60


@router.post("/login", response_model=schemas.LoginResponse)
@limiter.limit("10/minute")
def login(
    request: Request,
    payload: schemas.LoginRequest,
    db: Session = Depends(get_db),
):
    user = db.query(models.User).filter(models.User.email == payload.email.lower()).first()

    # Sprint B: bloqueio temporário por conta após N tentativas falhas. Rate
    # limit por IP (10/min) já existia mas era ineficaz contra credential
    # stuffing distribuído. O lockout por conta complementa.
    if user is not None and user.locked_until is not None and user.locked_until > utcnow():
        # Mensagem deliberadamente genérica — não revela que a conta existe.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials"
        )

    if user is None or not verify_password(payload.password, user.password_hash):
        if user is not None:
            user.failed_login_count = (user.failed_login_count or 0) + 1
            if user.failed_login_count >= _FAILED_LOGIN_THRESHOLD:
                # Backoff geométrico: 5 falhas → 60s, 6 → 120s, 7 → 240s...
                overflow = user.failed_login_count - _FAILED_LOGIN_THRESHOLD
                backoff = _FAILED_LOGIN_BACKOFF_BASE_SECONDS * (2 ** overflow)
                user.locked_until = utcnow() + timedelta(seconds=backoff)
                audit(db, user, "login_lockout", "user", str(user.id))
            db.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    # Sucesso: zera contadores.
    if user.failed_login_count or user.locked_until is not None:
        user.failed_login_count = 0
        user.locked_until = None

    # M2 — if TOTP is enabled, pause here and issue a pending session instead
    # of a full token pair. The client must complete /auth/2fa/verify.
    if user.totp_enabled:
        raw, digest, expires_at = generate_totp_pending_session()
        db.add(models.TotpPendingSession(
            user_id=user.id,
            session_hash=digest,
            expires_at=expires_at,
        ))
        audit(db, user, "login_totp_pending", "user", str(user.id))
        db.commit()
        return schemas.LoginResponse(requires_totp=True, pending_session_id=raw)

    audit(db, user, "login", "user", str(user.id))
    access, refresh = issue_token_pair(db, user)
    db.commit()
    return schemas.LoginResponse(
        access_token=access,
        refresh_token=refresh,
        user=user_read(db, user),
    )


@router.post("/refresh", response_model=schemas.TokenResponse)
@limiter.limit("30/minute")
def refresh_session(
    request: Request,
    payload: schemas.RefreshRequest,
    db: Session = Depends(get_db),
):
    """Trade a refresh token for a new access+refresh pair."""
    digest = hash_refresh_token(payload.refresh_token)
    record = db.query(models.RefreshToken).filter(models.RefreshToken.token_hash == digest).first()
    if record is None or record.revoked_at is not None or record.expires_at < utcnow():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

    user = db.query(models.User).filter(models.User.id == record.user_id).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")

    record.revoked_at = utcnow()
    access, refresh = issue_token_pair(db, user)
    audit(db, user, "refresh_session", "refresh_token", str(record.id))
    db.commit()
    return schemas.TokenResponse(
        access_token=access,
        refresh_token=refresh,
        user=user_read(db, user),
    )


@router.post("/logout", response_model=schemas.MessageResponse)
def logout(
    payload: schemas.LogoutRequest,
    db: Session = Depends(get_db),
    token: str = Depends(oauth2_scheme),
    user: models.User = Depends(current_user),
):
    """Revoke BOTH the supplied refresh token and the current bearer access
    token. The jti blacklist closes the residual TTL window."""
    digest = hash_refresh_token(payload.refresh_token)
    record = db.query(models.RefreshToken).filter(
        models.RefreshToken.token_hash == digest,
        models.RefreshToken.user_id == user.id,
    ).first()
    if record is not None and record.revoked_at is None:
        record.revoked_at = utcnow()
        audit(db, user, "logout", "refresh_token", str(record.id))

    access_payload = decode_access_token_payload(token) or {}
    jti = access_payload.get("jti")
    exp = access_payload.get("exp")
    if isinstance(jti, str) and jti and isinstance(exp, (int, float)):
        existing = db.query(models.RevokedAccessToken).filter_by(jti=jti).first()
        if existing is None:
            db.add(models.RevokedAccessToken(
                jti=jti,
                expires_at=datetime.fromtimestamp(exp, tz=timezone.utc),
            ))
            audit(db, user, "logout", "access_token", jti)

    db.commit()
    return schemas.MessageResponse(message="Sessao encerrada.")


@router.post("/password-reset", response_model=schemas.MessageResponse)
@limiter.limit("3/minute")
def request_password_reset(
    request: Request,
    payload: schemas.PasswordResetRequest,
    db: Session = Depends(get_db),
):
    user = db.query(models.User).filter(models.User.email == payload.email.lower()).first()
    if user is not None:
        reset_code = secrets.token_urlsafe(18)
        db.add(models.PasswordResetToken(
            user_id=user.id,
            token_hash=hash_reset_code(reset_code),
            expires_at=utcnow() + timedelta(minutes=30),
        ))
        sent = notifications.send_password_reset_email(user.email, reset_code)
        audit(db, user, "password_reset_requested", "user", str(user.id))
        if not sent:
            audit(db, user, "password_reset_email_not_configured", "user", str(user.id))
        db.commit()

    return schemas.MessageResponse(
        message="Se o e-mail estiver cadastrado, enviaremos instrucoes de recuperacao."
    )


@router.post("/password-reset/confirm", response_model=schemas.MessageResponse)
@limiter.limit("5/minute")
def confirm_password_reset(
    request: Request,
    payload: schemas.PasswordResetConfirm,
    db: Session = Depends(get_db),
):
    """Consume a single-use reset code. Returns 400 with a uniform message on
    any failure so an attacker cannot distinguish bad e-mail vs bad code."""
    generic_error = HTTPException(status_code=400, detail="Codigo invalido ou expirado.")

    user = db.query(models.User).filter(models.User.email == payload.email.lower()).first()
    if user is None:
        raise generic_error

    digest = hash_reset_code(payload.reset_code)
    record = db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.token_hash == digest,
        models.PasswordResetToken.user_id == user.id,
    ).first()
    if record is None or record.used_at is not None or record.expires_at < utcnow():
        raise generic_error

    user.password_hash = hash_password(payload.new_password)
    record.used_at = utcnow()

    db.query(models.RefreshToken).filter(
        models.RefreshToken.user_id == user.id,
        models.RefreshToken.revoked_at.is_(None),
    ).update({models.RefreshToken.revoked_at: utcnow()}, synchronize_session=False)
    user.token_epoch = user.token_epoch + 1

    audit(db, user, "password_reset_confirmed", "user", str(user.id))
    db.commit()
    return schemas.MessageResponse(message="Senha atualizada. Faca login novamente.")
