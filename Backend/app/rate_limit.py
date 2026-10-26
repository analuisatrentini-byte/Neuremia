"""Shared in-process rate limiter for the Neuremia API.

Sprint B Lote 4: agora respeita `X-Forwarded-For` quando atrás de proxy
(uvicorn precisa rodar com `--proxy-headers --forwarded-allow-ips=<lb_cidr>`)
e suporta storage Redis via `NEUREMIA_RATE_LIMIT_STORAGE_URI`. Sem proxy,
sem Redis: cai pro `get_remote_address` + in-memory original.

Disabled when `NEUREMIA_ENV=test` so the pytest suite can hammer auth
endpoints without tripping its own throttles.
"""
import os

from slowapi import Limiter
from slowapi.util import get_remote_address
from starlette.requests import Request


_RATE_LIMIT_ENABLED = os.getenv("NEUREMIA_ENV", "").lower() != "test"


def _client_identifier(request: Request) -> str:
    """Sprint B: identifier que respeita X-Forwarded-For quando configurado.

    Uvicorn precisa rodar com `--proxy-headers --forwarded-allow-ips=<cidr>`
    para que `request.client.host` reflita o cliente real e não o LB. Quando
    o trust list confere, lemos o header `X-Forwarded-For` (primeiro IP).
    Quando não há proxy, `get_remote_address` continua sendo a fonte.
    """
    if os.getenv("NEUREMIA_TRUST_PROXY_HEADERS", "").lower() in {"1", "true", "yes"}:
        forwarded = request.headers.get("x-forwarded-for") or ""
        first = forwarded.split(",")[0].strip()
        if first:
            return first
    return get_remote_address(request)


# Sprint B: storage_uri opcional para Redis. Em produção com N workers,
# storage in-memory significa que o limite efetivo é `N × declared_limit`.
# `redis://localhost:6379` ou `redis://user:pass@host:port/db` consolidam.
_storage_uri = os.getenv("NEUREMIA_RATE_LIMIT_STORAGE_URI", "")

_limiter_kwargs = {
    "key_func": _client_identifier,
    "default_limits": ["240/minute"],
    "enabled": _RATE_LIMIT_ENABLED,
}
if _storage_uri:
    _limiter_kwargs["storage_uri"] = _storage_uri

limiter = Limiter(**_limiter_kwargs)
