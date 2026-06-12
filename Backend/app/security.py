import hashlib
import os
import secrets as _secrets
from datetime import datetime, timedelta, timezone

# Sprint B: migrado de python-jose (deprecated + CVE-2024-33663/33664) para
# PyJWT (mantida ativamente). API próxima mas com diferenças:
#  - PyJWT exige `algorithms=[...]` em decode (já fazíamos)
#  - PyJWT levanta família InvalidTokenError; capturamos a base.
from cryptography.fernet import Fernet, InvalidToken
import jwt
from jwt.exceptions import InvalidTokenError as JWTError
from passlib.context import CryptContext


REFRESH_TOKEN_EXPIRE_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "30"))


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
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "30"))

password_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
field_cipher = Fernet(_require_fernet_key())


def hash_password(password: str) -> str:
    return password_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return password_context.verify(password, password_hash)


def create_access_token(subject: str, epoch: int = 0) -> tuple[str, str]:
    """Mint an access token. Returns (token, jti) so the caller can later
    revoke this specific token by adding the jti to the blacklist.

    `epoch` is the per-user revocation counter; tokens carrying an epoch
    below the user's current value are rejected globally (Sprint 15 / S47)."""
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    jti = _secrets.token_urlsafe(16)
    payload = {"sub": subject, "exp": expires_at, "jti": jti, "epoch": epoch}
    token = jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)
    return token, jti


def decode_access_token(token: str) -> str | None:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        subject = payload.get("sub")
        return subject if isinstance(subject, str) and subject else None
    except JWTError:
        return None


def decode_access_token_payload(token: str) -> dict | None:
    """Full claims payload for callers that need the jti or expiry. Returns
    None for any decode error, never raises."""
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None


def generate_refresh_token() -> tuple[str, str, datetime]:
    """Return (raw_token, sha256_hash, expires_at). Only the hash is persisted;
    the raw value is returned to the caller exactly once."""
    raw = _secrets.token_urlsafe(48)
    digest = hashlib.sha256(raw.encode()).hexdigest()
    expires_at = datetime.utcnow() + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    return raw, digest, expires_at


def hash_refresh_token(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode()).hexdigest()


def hash_reset_code(raw_code: str) -> str:
    return hashlib.sha256(raw_code.encode()).hexdigest()


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
        # Sprint B: dev retornava `value` (o ciphertext cru) como se fosse
        # plaintext — mascarava regressões e o teste passava verde com lixo.
        # Agora retorna marker explícito em dev e mantém o raise em prod.
        if IS_PRODUCTION:
            raise
        return "[encrypted:undecryptable]"
