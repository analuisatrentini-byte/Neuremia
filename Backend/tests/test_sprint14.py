"""Sprint 14 — access token revocation."""
from datetime import datetime, timedelta

from .conftest import login, register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_access_jwt_contains_jti(client):
    response = register(client, email="jti@example.com")
    access = response["access_token"]

    from jose import jwt
    import os

    decoded = jwt.decode(access, os.environ["NEUROFLOW_SECRET_KEY"], algorithms=["HS256"])
    assert "jti" in decoded
    assert len(decoded["jti"]) >= 10


def test_logout_revokes_access_token_within_ttl(client):
    """S34 regression: after /auth/logout the bearer access token must be
    rejected by current_user even though its TTL hasn't elapsed yet."""
    response = register(client, email="kill-jti@example.com")
    access = response["access_token"]
    refresh = response["refresh_token"]

    # Token works before logout.
    me_before = client.get("/me", headers=_bearer(access))
    assert me_before.status_code == 200

    logout = client.post(
        "/auth/logout",
        json={"refresh_token": refresh},
        headers=_bearer(access),
    )
    assert logout.status_code == 200

    # Token is now refused — without S34 this would still pass because exp
    # is 30 minutes in the future.
    me_after = client.get("/me", headers=_bearer(access))
    assert me_after.status_code == 401


def test_different_access_tokens_have_distinct_jtis(client):
    a = register(client, email="distinct-a@example.com")
    b = register(client, email="distinct-b@example.com")

    from jose import jwt
    import os

    key = os.environ["NEUROFLOW_SECRET_KEY"]
    jti_a = jwt.decode(a["access_token"], key, algorithms=["HS256"])["jti"]
    jti_b = jwt.decode(b["access_token"], key, algorithms=["HS256"])["jti"]
    assert jti_a != jti_b


def test_admin_purge_removes_expired_jti_blacklist_rows(client, admin_api_key):
    """Once a blacklisted access token would have expired naturally, its
    blacklist row becomes a no-op and the admin purge endpoint reaps it."""
    from app import database, models

    user = register(client, email="reap-jti@example.com")
    access = user["access_token"]
    refresh = user["refresh_token"]

    client.post("/auth/logout", json={"refresh_token": refresh}, headers=_bearer(access))

    with database.SessionLocal() as session:
        record = session.query(models.RevokedAccessToken).first()
        assert record is not None
        record.expires_at = datetime.utcnow() - timedelta(minutes=1)
        session.commit()

    response = client.post(
        "/admin/refresh-tokens/purge",
        headers={"X-Admin-API-Key": admin_api_key},
    )
    assert response.status_code == 200
    assert response.json()["deleted_access_token_jtis"] >= 1


def test_logout_twice_is_idempotent_on_blacklist(client):
    user = register(client, email="double-logout@example.com")
    access = user["access_token"]
    refresh = user["refresh_token"]

    first = client.post("/auth/logout", json={"refresh_token": refresh}, headers=_bearer(access))
    assert first.status_code == 200

    # Bearer is now revoked so the second logout call MUST be rejected by
    # current_user before reaching the body. This is the intended UX:
    # a logged-out token can't drive any more endpoints.
    second = client.post("/auth/logout", json={"refresh_token": refresh}, headers=_bearer(access))
    assert second.status_code == 401
