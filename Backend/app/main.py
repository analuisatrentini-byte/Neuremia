"""Neuremia FastAPI app entrypoint.

Routes live in dedicated modules under `app/routers/`. This file only wires
up middleware, the rate limiter, and the router inclusions. After Sprint 18
it's down to ~70 lines vs. 1.3k in the monolithic days.

Tests that depend on internal helpers (`_top_n_per_patient`, etc.) keep
working through the re-exports at the bottom of this module.
"""
import logging
import os
import time
import uuid

from fastapi import FastAPI, HTTPException, Request
from sqlalchemy import text
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from .apns import APNsSender
from .database import get_db
from .rate_limit import limiter
from .routers import (
    admin as admin_router,
    auth as auth_router,
    caregivers as caregivers_router,
    checkins as checkins_router,
    clinician as clinician_router,
    devices as devices_router,
    me as me_router,
    patients as patients_router,
    totp as totp_router,
)
from .services import (  # noqa: F401 — re-exported for tests
    _compute_risk_from_records,
    _top_n_per_patient,
    patient_risk_summary,
    patient_risk_summary_batch,
)


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("neuremia")

app = FastAPI(title="Neuremia API", version="1.0.0")


# ---- Security middlewares (Sprint 13 / S6) -----------------------------------

_allowed_origins_raw = os.getenv("NEUREMIA_ALLOWED_ORIGINS", "")
ALLOWED_ORIGINS = [o.strip() for o in _allowed_origins_raw.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Admin-API-Key"],
)

_allowed_hosts_raw = os.getenv("NEUREMIA_ALLOWED_HOSTS", "*")
ALLOWED_HOSTS = [h.strip() for h in _allowed_hosts_raw.split(",") if h.strip()]
app.add_middleware(TrustedHostMiddleware, allowed_hosts=ALLOWED_HOSTS)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)


def production_readiness_checks(
    *,
    env: str | None = None,
    database_url: str | None = None,
    allowed_hosts: list[str] | None = None,
    allowed_origins: list[str] | None = None,
    secret_key_present: bool | None = None,
    field_encryption_key_present: bool | None = None,
    admin_api_key_present: bool | None = None,
    backup_schedule: str | None = None,
    push_webhook_url: str | None = None,
    sms_webhook_url: str | None = None,
) -> list[dict[str, str]]:
    """Return deploy-readiness checks without exposing secret values.

    /health answers "is the process alive?". These checks answer "is this
    deployment configured like production?". They intentionally report only
    labels/statuses so logs and dashboards never leak credentials.
    """

    resolved_env = (env or os.getenv("NEUREMIA_ENV", "development")).strip().lower()
    resolved_database_url = database_url or os.getenv("DATABASE_URL", "")
    resolved_hosts = ALLOWED_HOSTS if allowed_hosts is None else allowed_hosts
    resolved_origins = ALLOWED_ORIGINS if allowed_origins is None else allowed_origins
    is_prod = resolved_env in {"production", "prod", "staging"}

    checks: list[dict[str, str]] = []

    def add(name: str, status: str, detail: str) -> None:
        checks.append({"name": name, "status": status, "detail": detail})

    add("environment", "pass" if resolved_env else "fail", f"NEUREMIA_ENV={resolved_env or 'missing'}")
    add(
        "database",
        "pass" if (not is_prod or resolved_database_url.startswith("postgresql")) else "fail",
        "PostgreSQL required in production" if is_prod else "SQLite allowed outside production",
    )
    add(
        "trusted_hosts",
        "pass" if (not is_prod or ("*" not in resolved_hosts and bool(resolved_hosts))) else "fail",
        "TrustedHost allowlist configured" if "*" not in resolved_hosts else "Wildcard host allowlist is unsafe for production",
    )
    add(
        "cors",
        "pass" if (not is_prod or bool(resolved_origins)) else "fail",
        "CORS origin allowlist configured" if resolved_origins else "No CORS origins configured",
    )

    secret_present = os.getenv("NEUREMIA_SECRET_KEY") is not None if secret_key_present is None else secret_key_present
    field_key_present = os.getenv("NEUREMIA_FIELD_ENCRYPTION_KEY") is not None if field_encryption_key_present is None else field_encryption_key_present
    admin_key_present = os.getenv("NEUREMIA_ADMIN_API_KEY") is not None if admin_api_key_present is None else admin_api_key_present
    add("jwt_secret", "pass" if (not is_prod or secret_present) else "fail", "JWT secret configured" if secret_present else "Missing JWT secret")
    add("field_encryption", "pass" if (not is_prod or field_key_present) else "fail", "Field encryption key configured" if field_key_present else "Missing Fernet key")
    add("admin_key", "pass" if (not is_prod or admin_key_present) else "fail", "Admin API key configured" if admin_key_present else "Missing admin API key")

    resolved_backup_schedule = backup_schedule if backup_schedule is not None else os.getenv("BACKUP_SCHEDULE", "")
    add(
        "backups",
        "pass" if (not is_prod or bool(resolved_backup_schedule.strip())) else "fail",
        "Backup schedule declared" if resolved_backup_schedule.strip() else "No backup schedule declared",
    )

    resolved_push = push_webhook_url if push_webhook_url is not None else os.getenv("PUSH_WEBHOOK_URL", "")
    resolved_sms = sms_webhook_url if sms_webhook_url is not None else os.getenv("SMS_WEBHOOK_URL", "")
    direct_push = APNsSender().enabled
    add(
        "critical_notifications",
        "pass" if (direct_push or resolved_push.startswith("https://") or not is_prod) else "warn",
        "APNs configured" if direct_push else ("APNs bridge configured" if resolved_push.startswith("https://") else "Push not configured"),
    )
    add(
        "caregiver_sms",
        "pass",
        "SMS bridge configured" if resolved_sms.startswith("https://") else "SMS disabled (optional)",
    )

    return checks


@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    request_id = str(uuid.uuid4())[:8]
    start = time.perf_counter()
    response = await call_next(request)
    duration_ms = round((time.perf_counter() - start) * 1000)
    logger.info(
        "%s %s %s %dms id=%s",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
        request_id,
    )
    response.headers["X-Request-Id"] = request_id
    return response


# ---- Routers (Sprint 17 + 18 / C32) ------------------------------------------

_V1 = "/v1"
app.include_router(auth_router.router, prefix=_V1)
app.include_router(admin_router.router, prefix=_V1)
app.include_router(me_router.router, prefix=_V1)
app.include_router(clinician_router.router, prefix=_V1)
app.include_router(patients_router.router, prefix=_V1)
app.include_router(caregivers_router.router, prefix=_V1)
app.include_router(checkins_router.router, prefix=_V1)
app.include_router(devices_router.router, prefix=_V1)
app.include_router(totp_router.router, prefix=_V1)


# ---- Misc --------------------------------------------------------------------


from sqlalchemy.orm import Session
from fastapi import Depends


@app.get("/health")
def health(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        return {"status": "ok", "db": "ok"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail={"status": "degraded", "db": str(exc)})


@app.get("/ready")
def ready(db: Session = Depends(get_db)):
    db_status = "ok"
    checks = production_readiness_checks()
    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:
        db_status = "failed"
        checks.append({"name": "db_connection", "status": "fail", "detail": str(exc)})

    failed = [check for check in checks if check["status"] == "fail"]
    warning = [check for check in checks if check["status"] == "warn"]
    status = "ready" if not failed else "not_ready"
    body = {
        "status": status,
        "db": db_status,
        "checks": checks,
        "summary": {
            "failed": len(failed),
            "warnings": len(warning),
        },
    }
    if failed:
        raise HTTPException(status_code=503, detail=body)
    return body
