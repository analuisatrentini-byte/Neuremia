"""Shared in-process rate limiter for the NeuroFlow API.

Disabled when `NEUROFLOW_ENV=test` so the pytest suite can hammer auth
endpoints without tripping its own throttles. Production deployments should
swap the in-memory backend for Redis once we scale beyond a single worker.
"""
import os

from slowapi import Limiter
from slowapi.util import get_remote_address


_RATE_LIMIT_ENABLED = os.getenv("NEUROFLOW_ENV", "").lower() != "test"

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["240/minute"],
    enabled=_RATE_LIMIT_ENABLED,
)
