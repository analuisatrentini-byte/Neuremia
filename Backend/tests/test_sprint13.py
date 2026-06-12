"""Sprint 13 — hardening regressions.

Covers:
- B29/P10: window-function batching keeps per-patient limit even when one
  patient has hundreds of records.
- S6: CORSMiddleware blocks disallowed origins (verified via Origin header).
- S9: password-reset confirm flow (success, wrong code, expired token, no email).
"""
from datetime import datetime, timedelta

from .conftest import login, promote_to_clinician, register


PATIENT_PAYLOAD = {
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
    "journal_entry": "ok",
}


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ------------ B29/P10 ------------

def test_batched_clinician_view_caps_per_patient(client, admin_api_key):
    from app import database, models

    # Setup: 1 clinician + 2 patients linked. One patient has 60 check-ins;
    # batch must still return at most 30 to the scoring function.
    register(client, email="b29-pat1@example.com")
    register(client, email="b29-pat2@example.com")
    register(client, email="b29-doc@example.com")
    promote_to_clinician(client, user_id=3, admin_key=admin_api_key)

    pat1_token = login(client, email="b29-pat1@example.com")
    pat2_token = login(client, email="b29-pat2@example.com")
    doc_token = login(client, email="b29-doc@example.com")

    # Invite + accept both patients
    for email, pat_token in (("b29-pat1@example.com", pat1_token), ("b29-pat2@example.com", pat2_token)):
        invite = client.post(
            "/clinician/invites",
            json={"patient_email": email},
            headers=_bearer(doc_token),
        )
        client.post(f"/me/invites/{invite.json()['id']}/accept", headers=_bearer(pat_token))

    for _ in range(60):
        client.post("/checkins", json=PATIENT_PAYLOAD, headers=_bearer(pat1_token))
    client.post("/checkins", json=PATIENT_PAYLOAD, headers=_bearer(pat2_token))

    # The clinician dashboard listing computes risk via batch — should return
    # both patients with a risk_level even though pat1 has 60 check-ins.
    response = client.get("/clinician/patients", headers=_bearer(doc_token))
    assert response.status_code == 200
    body = response.json()
    assert len(body) == 2
    for patient in body:
        assert patient["risk_score"] is not None
        assert patient["risk_level"] in {"low", "moderate", "high"}

    # And confirm at the SQL level that the window function is the one in use:
    # `_top_n_per_patient` returns max 30 for DailyCheckIn even with 60 in DB.
    from app.main import _top_n_per_patient

    with database.SessionLocal() as session:
        rows = _top_n_per_patient(
            session, models.DailyCheckIn, [1, 2], 30
        )
        # Pat1 contributes 30, pat2 contributes 1 → 31 rows total.
        assert len(rows) == 31
        per_patient: dict[int, int] = {}
        for row in rows:
            per_patient[row.patient_id] = per_patient.get(row.patient_id, 0) + 1
        assert per_patient[1] == 30
        assert per_patient[2] == 1


# ------------ S6 ------------

def test_cors_preflight_rejects_disallowed_origin(client, monkeypatch):
    # Override the allowed origins for this single request.
    monkeypatch.setenv("NEUROFLOW_ALLOWED_ORIGINS", "https://allowed.example.com")
    response = client.options(
        "/auth/login",
        headers={
            "Origin": "https://evil.example.com",
            "Access-Control-Request-Method": "POST",
        },
    )
    # Without the matching Origin, the response must not carry the
    # Access-Control-Allow-Origin header.
    assert response.headers.get("access-control-allow-origin") != "https://evil.example.com"


# ------------ S9 ------------

def test_password_reset_confirm_succeeds_with_valid_code(client, monkeypatch):
    """Exercise the full code path by capturing the raw code as the
    notification layer would have e-mailed it."""
    from app import notifications

    captured: dict[str, str] = {}

    def fake_send(recipient, reset_code):
        captured["recipient"] = recipient
        captured["code"] = reset_code
        return True

    monkeypatch.setattr(notifications.notifications, "send_password_reset_email", fake_send)

    register(client, email="reset-me@example.com")
    client.post("/auth/password-reset", json={"email": "reset-me@example.com"})

    assert captured["recipient"] == "reset-me@example.com"
    code = captured["code"]
    assert len(code) > 8

    confirm = client.post(
        "/auth/password-reset/confirm",
        json={
            "email": "reset-me@example.com",
            "reset_code": code,
            "new_password": "newsecret1",
        },
    )
    assert confirm.status_code == 200

    # Old password no longer works.
    bad = client.post(
        "/auth/login",
        json={"email": "reset-me@example.com", "password": "supersecret1"},
    )
    assert bad.status_code == 401

    # New password does.
    good = client.post(
        "/auth/login",
        json={"email": "reset-me@example.com", "password": "newsecret1"},
    )
    assert good.status_code == 200

    # Reusing the code now fails.
    replay = client.post(
        "/auth/password-reset/confirm",
        json={
            "email": "reset-me@example.com",
            "reset_code": code,
            "new_password": "yetanother1",
        },
    )
    assert replay.status_code == 400


def test_password_reset_confirm_uniform_error_on_bad_code(client):
    register(client, email="probe@example.com")
    response = client.post(
        "/auth/password-reset/confirm",
        json={
            "email": "probe@example.com",
            "reset_code": "definitely-not-issued-code",
            "new_password": "newsecret1",
        },
    )
    assert response.status_code == 400
    # Same error shape for completely unknown email.
    response2 = client.post(
        "/auth/password-reset/confirm",
        json={
            "email": "ghost@example.com",
            "reset_code": "anything",
            "new_password": "newsecret1",
        },
    )
    assert response2.status_code == 400
    assert response.json()["detail"] == response2.json()["detail"]


def test_password_reset_confirm_rejects_expired_token(client, monkeypatch):
    from app import database, models, notifications

    captured: dict[str, str] = {}

    def fake_send(recipient, reset_code):
        captured["code"] = reset_code
        return True

    monkeypatch.setattr(notifications.notifications, "send_password_reset_email", fake_send)

    register(client, email="late@example.com")
    client.post("/auth/password-reset", json={"email": "late@example.com"})

    with database.SessionLocal() as session:
        record = session.query(models.PasswordResetToken).first()
        record.expires_at = datetime.utcnow() - timedelta(minutes=1)
        session.commit()

    response = client.post(
        "/auth/password-reset/confirm",
        json={
            "email": "late@example.com",
            "reset_code": captured["code"],
            "new_password": "newsecret1",
        },
    )
    assert response.status_code == 400
