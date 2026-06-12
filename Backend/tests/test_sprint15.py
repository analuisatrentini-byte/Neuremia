"""Sprint 15 — per-user epoch revocation + admin force-logout + CASCADE FKs."""
from .conftest import login, register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ------------ S47 ------------

def test_password_reset_revokes_existing_access_token(client, monkeypatch):
    """S47 regression: an attacker holding the pre-reset access token must NOT
    be able to use it after the legitimate user changes the password."""
    from app import notifications

    captured: dict[str, str] = {}
    monkeypatch.setattr(
        notifications.notifications,
        "send_password_reset_email",
        lambda recipient, reset_code: (captured.update(code=reset_code), True)[1],
    )

    user = register(client, email="reset-revoke@example.com")
    stolen_access = user["access_token"]

    # Token works before reset.
    assert client.get("/me", headers=_bearer(stolen_access)).status_code == 200

    client.post("/auth/password-reset", json={"email": "reset-revoke@example.com"})
    confirm = client.post(
        "/auth/password-reset/confirm",
        json={
            "email": "reset-revoke@example.com",
            "reset_code": captured["code"],
            "new_password": "newsecret1",
        },
    )
    assert confirm.status_code == 200

    # Stolen access token must be rejected now even though its TTL is far
    # from elapsed.
    forbidden = client.get("/me", headers=_bearer(stolen_access))
    assert forbidden.status_code == 401


def test_password_reset_bumps_token_epoch(client, monkeypatch):
    from app import database, models, notifications

    captured: dict[str, str] = {}
    monkeypatch.setattr(
        notifications.notifications,
        "send_password_reset_email",
        lambda recipient, reset_code: (captured.update(code=reset_code), True)[1],
    )

    register(client, email="epoch@example.com")
    with database.SessionLocal() as session:
        user = session.query(models.User).filter_by(email="epoch@example.com").first()
        epoch_before = user.token_epoch

    client.post("/auth/password-reset", json={"email": "epoch@example.com"})
    client.post(
        "/auth/password-reset/confirm",
        json={
            "email": "epoch@example.com",
            "reset_code": captured["code"],
            "new_password": "newsecret1",
        },
    )

    with database.SessionLocal() as session:
        user = session.query(models.User).filter_by(email="epoch@example.com").first()
        assert user.token_epoch == epoch_before + 1


# ------------ F28 / S46 ------------

def test_admin_revoke_sessions_kills_active_tokens(client, admin_api_key):
    user = register(client, email="revoke-target@example.com")
    access = user["access_token"]
    refresh = user["refresh_token"]
    user_id = user["user"]["id"]

    response = client.post(
        f"/admin/users/{user_id}/revoke-sessions",
        headers={"X-Admin-API-Key": admin_api_key},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["new_token_epoch"] == 1
    assert body["revoked_refresh_tokens"] == 1

    # Access JWT now fails (token_epoch=0 < user.token_epoch=1).
    me = client.get("/me", headers=_bearer(access))
    assert me.status_code == 401

    # Refresh token also fails (was revoked).
    rotation = client.post("/auth/refresh", json={"refresh_token": refresh})
    assert rotation.status_code == 401


def test_admin_revoke_sessions_requires_admin_key(client):
    register(client, email="protected@example.com")
    response = client.post(
        "/admin/users/1/revoke-sessions",
        headers={"X-Admin-API-Key": "nope"},
    )
    assert response.status_code == 401


def test_admin_revoke_sessions_404_for_unknown_user(client, admin_api_key):
    response = client.post(
        "/admin/users/9999/revoke-sessions",
        headers={"X-Admin-API-Key": admin_api_key},
    )
    assert response.status_code == 404


# ------------ D4 ------------

def test_delete_my_account_cascades_through_all_user_tables(client):
    """D4 regression: removing a user must clear every per-user table via
    DB-level CASCADE, leaving only the audit trail behind (with NULL actor)."""
    from app import database, models

    register(client, email="cascade@example.com")
    token = login(client, email="cascade@example.com")
    user_id = (
        client.get("/me", headers=_bearer(token)).json()["id"]
    )

    # Generate some children rows across the tables we care about.
    client.post(
        "/checkins",
        json={
            "mood": 3,
            "anxiety": 2,
            "energy": 3,
            "irritability": 1,
            "sleep_hours": 7,
            "appetite": 3,
            "libido": 3,
            "medication_taken": True,
            "side_effects": "",
            "automatic_thoughts": "",
            "suicidal_ideation": False,
            "journal_entry": "x",
        },
        headers=_bearer(token),
    )
    client.post(
        "/caregivers",
        json={"name": "Mãe", "contact": "mae@example.com", "relationship": "mãe", "share_enabled": True},
        headers=_bearer(token),
    )

    delete = client.delete("/me", headers=_bearer(token))
    assert delete.status_code == 200

    with database.SessionLocal() as session:
        # User row gone.
        assert session.query(models.User).filter_by(id=user_id).first() is None
        # Children cascaded.
        assert session.query(models.DailyCheckIn).filter_by(patient_id=user_id).count() == 0
        assert session.query(models.CaregiverContact).filter_by(patient_id=user_id).count() == 0
        assert session.query(models.RefreshToken).filter_by(user_id=user_id).count() == 0
        # Audit log preserved with NULL actor.
        orphaned = session.query(models.AuditLog).filter(
            models.AuditLog.actor_user_id.is_(None)
        ).count()
        assert orphaned >= 3
