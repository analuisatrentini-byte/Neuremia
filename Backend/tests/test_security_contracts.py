"""Security contracts — NeuroFlow audit round 3.

Each test locks in a specific security or data-integrity behaviour so that
future refactors cannot silently regress it. Tests are grouped by the audit
finding they cover (C = critical, A = high).

Running:
    cd Backend && pytest tests/test_security_contracts.py -v
"""
import threading
import time

import pytest

from .conftest import grant_consent, login, promote_to_clinician, register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


CHECKIN = {
    "mood": 3, "anxiety": 2, "energy": 3, "irritability": 1,
    "sleep_hours": 7, "appetite": 3, "libido": 3,
    "medication_taken": True, "side_effects": "",
    "automatic_thoughts": "", "suicidal_ideation": False,
    "journal_entry": "test entry",
}

PHQ9_ANSWERS_9 = [1, 0, 1, 0, 1, 0, 1, 0, 0]   # 9 items — valid
PHQ9_ANSWERS_8 = [1, 0, 1, 0, 1, 0, 1, 0]        # 8 items — invalid
PHQ9_ANSWERS_10 = [1, 0, 1, 0, 1, 0, 1, 0, 0, 0] # 10 items — invalid


# ══════════════════════════════════════════════════════════════════════════════
# C3 — User enumeration via /auth/register
# ══════════════════════════════════════════════════════════════════════════════

class TestUserEnumeration:
    """POST /auth/register must never reveal whether an email already exists.

    Returning a distinct status code (409) for duplicates lets an attacker
    enumerate valid accounts in a psychiatric patient management system.
    The endpoint must respond identically for new and existing addresses.
    """

    def test_duplicate_email_does_not_return_409(self, client):
        register(client, email="existing@example.com")
        response = client.post(
            "/v1/auth/register",
            json={"email": "existing@example.com", "password": "supersecret1", "full_name": "Dup"},
        )
        assert response.status_code != 409, (
            "Registration with duplicate email returned 409 — attacker can enumerate "
            "registered patients by trying emails and checking for this status code."
        )

    def test_duplicate_and_new_email_return_same_status(self, client):
        register(client, email="first@example.com")

        dup = client.post(
            "/v1/auth/register",
            json={"email": "first@example.com", "password": "supersecret1", "full_name": "Dup"},
        )
        fresh = client.post(
            "/v1/auth/register",
            json={"email": "brand-new@example.com", "password": "supersecret1", "full_name": "New"},
        )
        assert dup.status_code == fresh.status_code, (
            f"Duplicate email returned {dup.status_code} but fresh email returned "
            f"{fresh.status_code}. Responses must be identical to prevent enumeration."
        )

    def test_duplicate_response_body_does_not_reveal_email_exists(self, client):
        register(client, email="secret@example.com")
        response = client.post(
            "/v1/auth/register",
            json={"email": "secret@example.com", "password": "supersecret1", "full_name": "Dup"},
        )
        body_text = response.text.lower()
        forbidden_phrases = ["already", "exists", "registered", "taken", "duplicate"]
        found = [p for p in forbidden_phrases if p in body_text]
        assert not found, (
            f"Registration error response contains enumeration hints: {found}. "
            f"Body: {response.text!r}"
        )


# ══════════════════════════════════════════════════════════════════════════════
# I2 / C9 — LGPD consent gate on clinical data endpoints
# ══════════════════════════════════════════════════════════════════════════════

class TestLgpdConsentGate:
    """POST /checkins, /assessments, /reports must refuse data submission when
    the patient has not granted clinical_data_storage consent.

    This is the primary LGPD Art. 7 II control: no clinical record is written
    without explicit, specific, and highlighted consent.
    """

    def test_checkin_requires_consent(self, client):
        register(client, email="noconsent_ci@example.com")
        token = login(client, email="noconsent_ci@example.com")

        response = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(token))
        assert response.status_code == 403, (
            f"POST /checkins accepted data without LGPD consent (got {response.status_code}). "
            "Clinical data must not be stored without explicit consent."
        )

    def test_assessment_requires_consent(self, client):
        register(client, email="noconsent_ass@example.com")
        token = login(client, email="noconsent_ass@example.com")

        response = client.post(
            "/v1/assessments",
            json={"scale_name": "PHQ-9", "answers": PHQ9_ANSWERS_9, "score": 4, "interpretation": "Mínimo"},
            headers=_bearer(token),
        )
        assert response.status_code == 403, (
            f"POST /assessments accepted data without LGPD consent (got {response.status_code})."
        )

    def test_report_requires_consent(self, client):
        register(client, email="noconsent_rep@example.com")
        token = login(client, email="noconsent_rep@example.com")

        response = client.post(
            "/v1/reports",
            json={"risk_level": "low", "summary": "Test summary"},
            headers=_bearer(token),
        )
        assert response.status_code == 403, (
            f"POST /reports accepted data without LGPD consent (got {response.status_code})."
        )

    def test_checkin_succeeds_after_consent_granted(self, client):
        register(client, email="withconsent_ci@example.com")
        token = login(client, email="withconsent_ci@example.com")
        grant_consent(client, token=token)

        response = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(token))
        assert response.status_code == 200, (
            f"POST /checkins failed after valid consent grant (got {response.status_code}): "
            f"{response.text}"
        )

    def test_checkin_blocked_after_consent_revoked(self, client):
        register(client, email="revoked_ci@example.com")
        token = login(client, email="revoked_ci@example.com")
        grant_consent(client, token=token)

        # Confirm it works first.
        ok = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(token))
        assert ok.status_code == 200

        # Revoke consent.
        client.delete("/v1/me/consents/clinical_data_storage", headers=_bearer(token))

        # Now must be blocked.
        blocked = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(token))
        assert blocked.status_code == 403, (
            "POST /checkins still accepted data after consent was revoked. "
            "LGPD Art. 15: controller must stop processing when consent is withdrawn."
        )

    def test_consent_status_reflected_in_list_endpoint(self, client):
        register(client, email="consent_list@example.com")
        token = login(client, email="consent_list@example.com")

        empty = client.get("/v1/me/consents", headers=_bearer(token))
        assert empty.status_code == 200
        assert empty.json() == []

        grant_consent(client, token=token, purpose="clinical_data_storage")
        one = client.get("/v1/me/consents", headers=_bearer(token))
        assert len(one.json()) == 1
        assert one.json()[0]["purpose"] == "clinical_data_storage"
        assert one.json()[0]["active"] is True

        client.delete("/v1/me/consents/clinical_data_storage", headers=_bearer(token))
        after_revoke = client.get("/v1/me/consents", headers=_bearer(token))
        assert after_revoke.json()[0]["active"] is False


# ══════════════════════════════════════════════════════════════════════════════
# C9 — Scale assessment answer count validation
# ══════════════════════════════════════════════════════════════════════════════

class TestScaleAnswerValidation:
    """The backend must reject scale assessments with the wrong number of answers.

    PHQ-9 requires exactly 9 answers (items 1–9 of the Kroenke 2001 scale).
    GAD-7 requires exactly 7. YMRS requires exactly 11. A submission with the
    wrong count produces a mathematically invalid score and may trigger
    incorrect clinical alerts.
    """

    @pytest.fixture
    def patient_token(self, client):
        register(client, email="scale_patient@example.com")
        token = login(client, email="scale_patient@example.com")
        grant_consent(client, token=token)
        return token

    def _post_assessment(self, client, token, scale, answers, score=4, band="Mínimo"):
        return client.post(
            "/v1/assessments",
            json={"scale_name": scale, "answers": answers, "score": score, "interpretation": band},
            headers=_bearer(token),
        )

    def test_phq9_accepts_9_answers(self, client, patient_token):
        resp = self._post_assessment(client, patient_token, "PHQ-9", PHQ9_ANSWERS_9)
        assert resp.status_code == 200, f"PHQ-9 with 9 answers was rejected: {resp.text}"

    def test_phq9_rejects_8_answers(self, client, patient_token):
        resp = self._post_assessment(client, patient_token, "PHQ-9", PHQ9_ANSWERS_8)
        assert resp.status_code == 422, (
            f"PHQ-9 with 8 answers was accepted (got {resp.status_code}). "
            "A PHQ-9 with fewer than 9 items produces an invalid depression score."
        )

    def test_phq9_rejects_10_answers(self, client, patient_token):
        resp = self._post_assessment(client, patient_token, "PHQ-9", PHQ9_ANSWERS_10)
        assert resp.status_code == 422, (
            f"PHQ-9 with 10 answers was accepted (got {resp.status_code}). "
            "Only exactly 9 answers are valid for PHQ-9."
        )

    def test_gad7_accepts_7_answers(self, client, patient_token):
        answers_7 = [0, 1, 0, 1, 0, 1, 0]
        resp = self._post_assessment(client, patient_token, "GAD-7", answers_7, score=3, band="Mínimo")
        assert resp.status_code == 200, f"GAD-7 with 7 answers was rejected: {resp.text}"

    def test_gad7_rejects_wrong_count(self, client, patient_token):
        answers_6 = [0, 1, 0, 1, 0, 1]
        resp = self._post_assessment(client, patient_token, "GAD-7", answers_6, score=3, band="Mínimo")
        assert resp.status_code == 422, (
            f"GAD-7 with 6 answers was accepted (got {resp.status_code})."
        )

    def test_empty_answers_rejected(self, client, patient_token):
        resp = self._post_assessment(client, patient_token, "PHQ-9", [])
        assert resp.status_code == 422, (
            f"PHQ-9 with empty answers list was accepted (got {resp.status_code})."
        )

    def test_answers_must_be_integers_in_range(self, client, patient_token):
        answers_out_of_range = [0, 1, 0, 1, 0, 1, 0, 99, 0]  # 99 is out of 0-3 range
        resp = self._post_assessment(client, patient_token, "PHQ-9", answers_out_of_range)
        assert resp.status_code == 422, (
            f"PHQ-9 with out-of-range answer (99) was accepted (got {resp.status_code})."
        )


# ══════════════════════════════════════════════════════════════════════════════
# C4 — datetime timezone in TOTP pending session
# ══════════════════════════════════════════════════════════════════════════════

class TestTotpDatetimeSafety:
    """TotpPendingSession.expires_at must remain timezone-aware.

    security.py previously stripped tzinfo with .replace(tzinfo=None), making
    expires_at a naive datetime. Comparing a naive datetime with a timezone-aware
    one raises TypeError in Python 3.11+ and produces incorrect results in earlier
    versions — effectively disabling TOTP expiry enforcement.
    """

    def test_totp_pending_session_expires_at_is_timezone_aware(self, client):
        from app import database, models

        register(client, email="totp_tz@example.com")
        token = login(client, email="totp_tz@example.com")

        # Enable TOTP — creates a TotpSecret row.
        setup = client.post("/v1/auth/2fa/setup", headers=_bearer(token))
        if setup.status_code != 200:
            pytest.skip("TOTP setup endpoint not available in this build")

        # Trigger a login that requires TOTP (creates TotpPendingSession).
        import pyotp
        secret = setup.json().get("secret")
        if not secret:
            pytest.skip("No secret returned from TOTP setup")

        # Confirm TOTP to enable it.
        code = pyotp.TOTP(secret).now()
        confirm = client.post("/v1/auth/2fa/confirm", json={"code": code}, headers=_bearer(token))
        if confirm.status_code != 200:
            pytest.skip("TOTP confirm failed — cannot create pending session")

        # Login again — with TOTP enabled this creates a TotpPendingSession.
        login_resp = client.post(
            "/v1/auth/login",
            json={"email": "totp_tz@example.com", "password": "supersecret1"},
        )
        if not login_resp.json().get("requires_totp"):
            pytest.skip("Login did not require TOTP — cannot check pending session")

        # Inspect the pending session row directly.
        with database.SessionLocal() as session:
            pending = session.query(models.TotpPendingSession).first()
            assert pending is not None, "No TotpPendingSession was created"
            assert pending.expires_at.tzinfo is not None, (
                "TotpPendingSession.expires_at is a naive datetime (tzinfo=None). "
                "Comparison with datetime.now(timezone.utc) will raise TypeError "
                "in Python 3.11+ and silently pass expired sessions in older versions."
            )


# ══════════════════════════════════════════════════════════════════════════════
# C7 — /health must not leak database connection details
# ══════════════════════════════════════════════════════════════════════════════

class TestHealthEndpointSafety:
    """GET /health must not include exception details in its response body.

    In a failure scenario, str(exc) from SQLAlchemy can contain the full
    database DSN including host, port, username, and password.
    """

    def test_health_returns_200_when_db_is_up(self, client):
        response = client.get("/health")
        assert response.status_code == 200
        body = response.json()
        assert body.get("status") == "ok"
        assert body.get("db") == "ok"

    def test_health_success_body_contains_no_url(self, client):
        response = client.get("/health")
        body_text = response.text
        assert "sqlite" not in body_text, (
            "/health response leaks the database URL (contains 'sqlite'). "
            "The DSN must never appear in a public endpoint response."
        )
        assert "postgresql" not in body_text.lower()
        assert "password" not in body_text.lower()


# ══════════════════════════════════════════════════════════════════════════════
# C6 — TOTP single-use enforcement
# ══════════════════════════════════════════════════════════════════════════════

class TestTotpSingleUse:
    """A TOTP pending_session_id must be consumed exactly once.

    If two requests race with the same pending_session_id, only one should
    succeed. The second must return 4xx — not a duplicate token pair.
    """

    def test_totp_pending_session_cannot_be_reused(self, client):
        register(client, email="totp_race@example.com")
        token = login(client, email="totp_race@example.com")

        setup = client.post("/v1/auth/2fa/setup", headers=_bearer(token))
        if setup.status_code != 200:
            pytest.skip("TOTP setup not available")

        import pyotp
        secret = setup.json().get("secret")
        if not secret:
            pytest.skip("No secret from TOTP setup")

        code = pyotp.TOTP(secret).now()
        confirm = client.post("/v1/auth/2fa/confirm", json={"code": code}, headers=_bearer(token))
        if confirm.status_code != 200:
            pytest.skip("TOTP confirm failed")

        login_resp = client.post(
            "/v1/auth/login",
            json={"email": "totp_race@example.com", "password": "supersecret1"},
        )
        body = login_resp.json()
        if not body.get("requires_totp"):
            pytest.skip("TOTP login did not require OTP step")

        pending_id = body["pending_session_id"]
        otp = pyotp.TOTP(secret).now()

        # First verify — must succeed.
        r1 = client.post("/v1/auth/2fa/verify", json={"pending_session_id": pending_id, "code": otp})
        assert r1.status_code == 200, f"First TOTP verify failed: {r1.text}"

        # Second verify with same pending_session_id — must fail.
        r2 = client.post("/v1/auth/2fa/verify", json={"pending_session_id": pending_id, "code": otp})
        assert r2.status_code != 200, (
            f"TOTP pending_session_id was accepted twice (both returned 200). "
            "This allows replay attacks: a stolen pending_session_id can be reused "
            "to obtain a second valid token pair."
        )


# ══════════════════════════════════════════════════════════════════════════════
# A5 — Offline queue safety (backend side): duplicate checkin not upserted
# ══════════════════════════════════════════════════════════════════════════════

class TestCheckinIdempotency:
    """POST /checkins is NOT idempotent — each call creates a new record.

    The iOS client is responsible for deduplication before submitting offline
    queue items. The backend must store each submission as a distinct row to
    ensure the full clinical history is preserved.
    """

    def test_two_identical_checkins_create_two_records(self, client):
        register(client, email="idem@example.com")
        token = login(client, email="idem@example.com")
        grant_consent(client, token=token)

        r1 = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(token))
        r2 = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(token))
        assert r1.status_code == 200
        assert r2.status_code == 200
        assert r1.json()["id"] != r2.json()["id"], (
            "Two identical POST /checkins returned the same ID — the server is "
            "silently deduplicating check-ins, which would hide repeated symptoms."
        )

        export = client.get("/v1/me/export", headers=_bearer(token)).json()
        assert len(export["checkins"]) == 2


# ══════════════════════════════════════════════════════════════════════════════
# A10 — Risk cache freshness
# ══════════════════════════════════════════════════════════════════════════════

class TestRiskCacheFreshness:
    """After a new check-in, the clinician view must reflect updated risk.

    update_risk_cache() is called synchronously in POST /checkins, so the risk
    score visible to a linked clinician must change immediately — not require a
    background job or manual refresh.
    """

    def test_risk_updates_after_high_risk_checkin(self, client, admin_api_key):
        patient = register(client, email="risk_patient@example.com")
        clinician = register(client, email="risk_doc@example.com")
        promote_to_clinician(
            client, user_id=clinician["user"]["id"], admin_key=admin_api_key
        )

        pat_token = login(client, email="risk_patient@example.com")
        doc_token = login(client, email="risk_doc@example.com")
        grant_consent(client, token=pat_token)

        # Link patient to clinician.
        inv = client.post(
            "/v1/clinician/invites",
            json={"patient_email": "risk_patient@example.com"},
            headers=_bearer(doc_token),
        ).json()
        client.post(f"/v1/me/invites/{inv['id']}/accept", headers=_bearer(pat_token))

        # Baseline: no check-ins yet.
        before_raw = client.get("/v1/clinician/patients", headers=_bearer(doc_token)).json()
        before = before_raw.get("items", before_raw) if isinstance(before_raw, dict) else before_raw
        patient_id = patient["user"]["id"]
        before_patient = next(p for p in before if p["id"] == patient_id)

        # Submit a high-risk check-in (suicidal ideation = True).
        high_risk = {**CHECKIN, "suicidal_ideation": True, "mood": 0, "anxiety": 5}
        client.post("/v1/checkins", json=high_risk, headers=_bearer(pat_token))

        after_raw = client.get("/v1/clinician/patients", headers=_bearer(doc_token)).json()
        after = after_raw.get("items", after_raw) if isinstance(after_raw, dict) else after_raw
        after_patient = next(p for p in after if p["id"] == patient_id)

        assert after_patient["risk_score"] is not None, (
            "risk_score is None after a high-risk check-in — cache was not updated."
        )
        assert after_patient["risk_level"] == "high", (
            f"Expected risk_level='high' after suicidal ideation + mood=0, "
            f"got '{after_patient['risk_level']}'. "
            "Risk cache may not have been refreshed after POST /checkins."
        )


# ══════════════════════════════════════════════════════════════════════════════
# Admin purge — TotpPendingSession included
# ══════════════════════════════════════════════════════════════════════════════

class TestAdminPurge:
    """POST /admin/refresh-tokens/purge must clean TotpPendingSession rows
    and report the count in deleted_totp_pending_sessions."""

    def test_purge_response_includes_totp_field(self, client, admin_api_key):
        response = client.post(
            "/v1/admin/refresh-tokens/purge",
            headers={"X-Admin-API-Key": admin_api_key},
        )
        assert response.status_code == 200
        body = response.json()
        assert "deleted_totp_pending_sessions" in body, (
            "Admin purge response is missing 'deleted_totp_pending_sessions'. "
            "TotpPendingSession rows accumulate without cleanup, creating an "
            "ever-growing table and potential attack surface."
        )
        assert isinstance(body["deleted_totp_pending_sessions"], int)

    def test_purge_removes_expired_totp_sessions(self, client, admin_api_key):
        from datetime import datetime, timedelta, timezone
        from app import database, models

        # Manually insert an expired TotpPendingSession.
        with database.SessionLocal() as session:
            register(client, email="totp_purge@example.com")
            user = session.query(models.User).filter_by(email="totp_purge@example.com").first()
            expired = models.TotpPendingSession(
                user_id=user.id,
                session_hash="expired-hash-for-purge-test",
                expires_at=datetime.now(timezone.utc) - timedelta(hours=1),
            )
            session.add(expired)
            session.commit()

        response = client.post(
            "/v1/admin/refresh-tokens/purge",
            headers={"X-Admin-API-Key": admin_api_key},
        )
        assert response.status_code == 200
        assert response.json()["deleted_totp_pending_sessions"] >= 1, (
            "Admin purge did not delete the expired TotpPendingSession. "
            "Expired sessions must be cleaned to prevent table bloat."
        )
