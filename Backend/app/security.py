import os
import secrets as _secrets
from datetime import datetime, timedelta, timezone

from cryptography.fernet import Fernet, InvalidToken
from jose import JWTError, jwt
from passlib.context import CryptContext


ENV = os.getenv("NEUROFLOW_ENV", "development").strip().lower()
IS_PRODUCTION = ENV in {"production", "prod", "staging"}


def _require_env(name: str, *, generate_hint: str) -> str:
    value = os.getenv(name)
    if value and value.strip():
        return value.strip()

    if IS_PRODUCTION:
        raise RuntimeError(
            f"{name} must be set in {ENV}. Generate one with: {generate_hint}"
        )

    # Development convenience: stable per-process random secret so JWTs verify
    # across requests within the same boot but never persist or leak to prod.
    return _secrets.token_urlsafe(64)


def _require_fernet_key() -> bytes:
    configured = os.getenv("NEUROFLOW_FIELD_ENCRYPTION_KEY")
    if configured and configured.strip():
        return configured.strip().encode()

    if IS_PRODUCTION:
        raise RuntimeError(
            "NEUROFLOW_FIELD_ENCRYPTION_KEY must be set in production. "
            "Generate one with: python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
        )

    # Development convenience only: ephemeral key. Encrypted data is lost on
    # restart, which is exactly what we want for non-production environments.
    return Fernet.generate_key()


SECRET_KEY = _require_env(
    "NEUROFLOW_SECRET_KEY",
    generate_hint="python -c \"import secrets; print(secrets.token_urlsafe(64))\"",
)

ADMIN_API_KEY = _require_env(
    "NEUROFLOW_ADMIN_API_KEY",
    generate_hint="python -c \"import secrets; print(secrets.token_urlsafe(48))\"",
)

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "120"))

password_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
field_cipher = Fernet(_require_fernet_key())


def hash_password(password: str) -> str:
    return password_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return password_context.verify(password, password_hash)


def create_access_token(subject: str) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {"sub": subject, "exp": expires_at}
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> str | None:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        subject = payload.get("sub")
        return subject if isinstance(subject, str) and subject else None
    except JWTError:
        return None


def verify_admin_api_key(provided: str | None) -> bool:
    if not provided:
        return False
    return _secrets.compare_digest(provided, ADMIN_API_KEY)


def encrypt_field(value: str | None) -> str:
    if not value:
        return ""

    return field_cipher.encrypt(value.encode()).decode()


def decrypt_field(value: str | None) -> str:
    if not value:
        return ""

    try:
        return field_cipher.decrypt(value.encode()).decode()
    except InvalidToken:
        # In production, refuse to leak plaintext that does not round-trip through
        # the configured key. In development we keep the old behavior for legacy
        # records written before encryption was wired up.
        if IS_PRODUCTION:
            raise
        return value
