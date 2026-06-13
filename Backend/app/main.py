"""NeuroFlow FastAPI app entrypoint.

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
logger = logging.getLogger("neuroflow")

app = FastAPI(title="NeuroFlow API", version="1.0.0")


# ---- Security middlewares (Sprint 13 / S6) -----------------------------------

_allowed_origins_raw = os.getenv("NEUROFLOW_ALLOWED_ORIGINS", "")
ALLOWED_ORIGINS = [o.strip() for o in _allowed_origins_raw.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Admin-API-Key"],
)

_allowed_hosts_raw = os.getenv("NEUROFLOW_ALLOWED_HOSTS", "*")
ALLOWED_HOSTS = [h.strip() for h in _allowed_hosts_raw.split(",") if h.strip()]
app.add_middleware(TrustedHostMiddleware, allowed_hosts=ALLOWED_HOSTS)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)


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
