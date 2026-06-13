"""End-to-end tests for the three most critical NeuroFlow user flows.

These tests exercise the full HTTP stack (registration → authentication →
clinical data → clinician access) against an isolated SQLite database, with
foreign-key pragmas enabled to validate CASCADE behaviour.

Flows covered:
  1. Patient: register → login → create check-in → verify stored + audit log
  2. Clinician link: patient invites clinician → clinician accepts → reads data
  3. High-risk check-in: suicidal_ideation=True creates alert visible to clinician
"""
import datetime

import pytest

from .conftest import grant_consent, login, promote_to_clinician, register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


HIGH_RISK_CHECKIN = {
    "mood": 1,
    "anxiety": 5,
    "energy": 1,
    "irritability": 4,
    "sleep_hours": 3,
    "appetite": 1,
    "libido": 0,
    "medication_taken": False,
    "side_effects": "tontura",
    "automatic_thoughts": "sem saída",
    "suicidal_ideation": True,
    "journal_entry": "não aguento mais",
}

NORMAL_CHECKIN = {
    "mood": 4,
    "anxiety": 2,
    "energy": 4,
    "irritability": 1,
    "sleep_hours": 8,
    "appetite": 4,
    "libido": 3,
    "medication_taken": True,
    "side_effects": "",
    "automatic_thoughts": "",
    "suicidal_ideation": False,
    "journal_entry": "dia tranquilo",
}


# ---------------------------------------------------------------------------
# Flow 1: Patient registers, logs in, creates check-in, data is persisted
# and appears in audit log
# ---------------------------------------------------------------------------

def test_patient_register_login_checkin_auditlog(client):
    """Full patient happy path: registration → check-in → export includes data."""
    reg = register(client, email="flow1@example.com", full_name="Flow One")
    assert reg["access_token"]

    token = login(client, email="flow1@example.com")
    grant_consent(client, token=token)

    # Create a check-in
    resp = client.post("/v1/checkins", json=NORMAL_CHECKIN, headers=_bearer(token))
    assert resp.status_code == 200
    checkin_id = resp.json()["id"]
    assert checkin_id > 0

    # Export must include the check-in
    export = client.get("/v1/me/export", headers=_bearer(token)).json()
    assert any(ci["id"] == checkin_id for ci in export["checkins"])

    # create_checkin must appear in audit trail
    actions = {entry["action"] for entry in export["audit_logs"]}
    assert "create_checkin" in actions

    # PHI fields must be decrypted in the export (Fernet round-trip)
    checkin_export = next(ci for ci in export["checkins"] if ci["id"] == checkin_id)
    assert checkin_export["journal_entry"] == "dia tranquilo"


def test_multiple_checkins_are_stored_independently(client):
    """The backend stores each POST /checkins as a distinct record (no server-side upsert).
    Same-day deduplication is the iOS client's responsibility via @Attribute(.unique) dayKey.
    Both records must appear in the patient's export."""
    register(client, email="multi_checkin@example.com")
    token = login(client, email="multi_checkin@example.com")
    grant_consent(client, token=token)

    first = client.post("/v1/checkins", json=NORMAL_CHECKIN, headers=_bearer(token))
    assert first.status_code == 200

    updated = {**NORMAL_CHECKIN, "mood": 5, "journal_entry": "segundo registro"}
    second = client.post("/v1/checkins", json=updated, headers=_bearer(token))
    assert second.status_code == 200

    export = client.get("/v1/me/export", headers=_bearer(token)).json()
    assert len(export["checkins"]) == 2
    moods = {ci["mood"] for ci in export["checkins"]}
    assert moods == {4.0, 5.0}


# ---------------------------------------------------------------------------
# Flow 2: Clinician link flow — patient invites clinician, clinician accepts,
# clinician can read patient check-ins; unlinked clinician is blocked
# ---------------------------------------------------------------------------

def test_clinician_link_and_data_access(client, admin_api_key):
    """Clinician can only read patient data after the link is established."""
    # Setup patient
    patient_data = register(client, email="patient2@example.com")
    patient_token = login(client, email="patient2@example.com")
    grant_consent(client, token=patient_token)
    client.post("/v1/checkins", json=NORMAL_CHECKIN, headers=_bearer(patient_token))

    # Setup clinician
    clinician_data = register(client, email="clinician2@example.com", full_name="Dr. Test")
    promote_to_clinician(client, user_id=clinician_data["user"]["id"], admin_key=admin_api_key)
    clinician_token = login(client, email="clinician2@example.com")

    patient_id = patient_data["user"]["id"]

    # Before link: clinician must NOT see patient data
    pre = client.get(
        f"/v1/patients/{patient_id}/checkins",
        headers=_bearer(clinician_token),
    )
    assert pre.status_code == 403

    # Clinician invites patient (correct flow: clinician sends, patient accepts)
    invite_resp = client.post(
        "/v1/clinician/invites",
        json={"patient_email": "patient2@example.com"},
        headers=_bearer(clinician_token),
    )
    assert invite_resp.status_code == 200
    invite_id = invite_resp.json()["id"]

    # Patient accepts
    accept = client.post(
        f"/v1/me/invites/{invite_id}/accept",
        headers=_bearer(patient_token),
    )
    assert accept.status_code == 200

    # After link: clinician CAN read patient check-ins
    post = client.get(
        f"/v1/patients/{patient_id}/checkins",
        headers=_bearer(clinician_token),
    )
    assert post.status_code == 200
    assert len(post.json()) >= 1

    # Access is recorded in the clinician's own audit log
    # (actor_user_id = clinician — not the patient)
    clinician_audit = client.get("/v1/me/audit-logs", headers=_bearer(clinician_token)).json()
    assert any(
        entry["action"] == "read_patient_checkins"
        and entry["resource_id"] == str(patient_id)
        for entry in clinician_audit
    )


def test_unlinked_clinician_cannot_access_patient(client, admin_api_key):
    """A clinician with no link to a patient receives 403 on all PHI endpoints."""
    patient_data = register(client, email="isolated_patient@example.com")
    patient_token = login(client, email="isolated_patient@example.com")
    grant_consent(client, token=patient_token)
    patient_id = patient_data["user"]["id"]
    client.post("/v1/checkins", json=NORMAL_CHECKIN, headers=_bearer(patient_token))

    other = register(client, email="other_clinician@example.com")
    promote_to_clinician(client, user_id=other["user"]["id"], admin_key=admin_api_key)
    other_token = login(client, email="other_clinician@example.com")

    for endpoint in [
        f"/v1/patients/{patient_id}/checkins",
        f"/v1/patients/{patient_id}/assessments",
        f"/v1/patients/{patient_id}/alerts",
        f"/v1/patients/{patient_id}/reports",
    ]:
        resp = client.get(endpoint, headers=_bearer(other_token))
        assert resp.status_code == 403, f"{endpoint} should be 403 for unlinked clinician"


# ---------------------------------------------------------------------------
# Flow 3: High-risk check-in with suicidal_ideation=True — alert is created,
# clinician reads it, audit trail is complete
# ---------------------------------------------------------------------------

def test_high_risk_checkin_creates_alert_visible_to_linked_clinician(client, admin_api_key):
    """suicidal_ideation=True must create a ClinicalAlert accessible to the linked clinician."""
    patient_data = register(client, email="highrisk@example.com")
    patient_token = login(client, email="highrisk@example.com")
    grant_consent(client, token=patient_token)
    patient_id = patient_data["user"]["id"]

    clinician_data = register(client, email="clinician_hr@example.com", full_name="Dr. Risk")
    promote_to_clinician(client, user_id=clinician_data["user"]["id"], admin_key=admin_api_key)
    clinician_token = login(client, email="clinician_hr@example.com")

    # Link: clinician invites patient, patient accepts
    invite = client.post(
        "/v1/clinician/invites",
        json={"patient_email": "highrisk@example.com"},
        headers=_bearer(clinician_token),
    )
    assert invite.status_code == 200
    client.post(
        f"/v1/me/invites/{invite.json()['id']}/accept",
        headers=_bearer(patient_token),
    )

    # Patient submits high-risk check-in
    resp = client.post("/v1/checkins", json=HIGH_RISK_CHECKIN, headers=_bearer(patient_token))
    assert resp.status_code == 200

    # Alert must exist and be visible to linked clinician
    alerts = client.get(
        f"/v1/patients/{patient_id}/alerts",
        headers=_bearer(clinician_token),
    )
    assert alerts.status_code == 200
    alert_list = alerts.json()
    assert len(alert_list) >= 1, "High-risk check-in must generate at least one alert"

    levels = {a["level"] for a in alert_list}
    assert "high" in levels, f"Expected a high-level alert, got levels: {levels}"

    # Audit log must record the clinician reading alerts (stored under clinician's actor_user_id)
    clinician_audit = client.get("/v1/me/audit-logs", headers=_bearer(clinician_token)).json()
    assert any(
        entry["action"] == "read_patient_alerts"
        for entry in clinician_audit
    )


def test_high_risk_suicidal_flag_stored_on_checkin(client):
    """suicidal_ideation is persisted and returned in the export, not silently dropped."""
    register(client, email="suicidal_flag@example.com")
    token = login(client, email="suicidal_flag@example.com")
    grant_consent(client, token=token)
    client.post("/v1/checkins", json=HIGH_RISK_CHECKIN, headers=_bearer(token))

    export = client.get("/v1/me/export", headers=_bearer(token)).json()
    assert export["checkins"][0]["suicidal_ideation"] is True
