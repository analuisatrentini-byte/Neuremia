"""NeuroFlow FastAPI app entrypoint.

Routes live in dedicated modules under `app/routers/`. This file only wires
up middleware, the rate limiter, and the router inclusions. After Sprint 18
it's down to ~70 lines vs. 1.3k in the monolithic days.

Tests that depend on internal helpers (`_top_n_per_patient`, etc.) keep
working through the re-exports at the bottom of this module.
"""
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

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
)
from .services import (  # noqa: F401 — re-exported for tests
    _compute_risk_from_records,
    _top_n_per_patient,
    patient_risk_summary,
    patient_risk_summary_batch,
)


app = FastAPI(title="NeuroFlow API", version="0.1.0")


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


# ---- Routers (Sprint 17 + 18 / C32) ------------------------------------------

app.include_router(auth_router.router)
app.include_router(admin_router.router)
app.include_router(me_router.router)
app.include_router(clinician_router.router)
app.include_router(patients_router.router)
app.include_router(caregivers_router.router)
app.include_router(checkins_router.router)
app.include_router(devices_router.router)


# ---- Misc --------------------------------------------------------------------


@app.get("/health")
def health():
    return {"status": "ok"}
