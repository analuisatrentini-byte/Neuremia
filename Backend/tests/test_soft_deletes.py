"""Tests for B6 — soft deletes on DailyCheckIn, ClinicalAlert, ClinicalReport.

Verifies:
- DELETE /checkins/{id} soft-deletes (returns 200, second delete → 404)
- Soft-deleted checkins excluded from clinician /patients/{id}/checkins
- Soft-deleted checkins excluded from patient /me/export
- DELETE /checkins/{id} restricted to patient role (clinician → 403)
- DELETE /checkins/{id} on another patient's checkin → 404
- Audit log records delete_checkin action
"""
from .conftest import grant_consent, login, promote_to_clinician, register

CHECKIN = {
    "mood": 3, "anxiety": 2, "energy": 3, "irritability": 2,
    "sleep_hours": 7, "appetite": 3, "libido": 2.0,
    "medication_taken": True, "side_effects": "",
    "automatic_thoughts": "", "suicidal_ideation": False,
    "journal_entry": "b6 test",
}


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _pat(client, email):
    register(client, email=email)
    token = login(client, email=email)
    grant_consent(client, token=token)
    return token


def _setup_patient_clinician(client, admin_api_key, suffix=""):
    pat_token = _pat(client, f"b6pat{suffix}@test.com")
    cli_data = register(client, email=f"b6cli{suffix}@test.com")
    promote_to_clinician(client, user_id=cli_data["user"]["id"], admin_key=admin_api_key)
    cli_token = login(client, email=f"b6cli{suffix}@test.com")
    pat_email = f"b6pat{suffix}@test.com"
    pat_id = client.get("/v1/me", headers=_bearer(pat_token)).json()["id"]
    inv = client.post("/v1/clinician/invites", json={"patient_email": pat_email}, headers=_bearer(cli_token)).json()
    client.post(f"/v1/me/invites/{inv['id']}/accept", headers=_bearer(pat_token))
    return pat_token, cli_token, pat_id


# ---------------------------------------------------------------------------
# DELETE /checkins/{id} — basic soft delete
# ---------------------------------------------------------------------------

def test_delete_checkin_returns_200(client, admin_api_key):
    pat_token = _pat(client, "sd1@test.com")
    checkin_id = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat_token)).json()["id"]

    resp = client.delete(f"/v1/checkins/{checkin_id}", headers=_bearer(pat_token))
    assert resp.status_code == 200
    assert resp.json()["message"] == "Check-in removido."


def test_delete_checkin_second_call_returns_404(client, admin_api_key):
    pat_token = _pat(client, "sd2@test.com")
    checkin_id = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat_token)).json()["id"]

    client.delete(f"/v1/checkins/{checkin_id}", headers=_bearer(pat_token))
    resp = client.delete(f"/v1/checkins/{checkin_id}", headers=_bearer(pat_token))
    assert resp.status_code == 404


def test_delete_checkin_nonexistent_returns_404(client, admin_api_key):
    pat_token = _pat(client, "sd3@test.com")
    resp = client.delete("/v1/checkins/999999", headers=_bearer(pat_token))
    assert resp.status_code == 404


def test_delete_checkin_foreign_patient_returns_404(client, admin_api_key):
    pat1_token = _pat(client, "sd4a@test.com")
    pat2_token = _pat(client, "sd4b@test.com")
    checkin_id = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat1_token)).json()["id"]

    resp = client.delete(f"/v1/checkins/{checkin_id}", headers=_bearer(pat2_token))
    assert resp.status_code == 404


def test_delete_checkin_clinician_role_forbidden(client, admin_api_key):
    cli_data = register(client, email="sd5cli@test.com")
    promote_to_clinician(client, user_id=cli_data["user"]["id"], admin_key=admin_api_key)
    cli_token = login(client, email="sd5cli@test.com")

    pat_token = _pat(client, "sd5pat@test.com")
    checkin_id = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat_token)).json()["id"]

    resp = client.delete(f"/v1/checkins/{checkin_id}", headers=_bearer(cli_token))
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# Clinician view excludes soft-deleted checkins
# ---------------------------------------------------------------------------

def test_clinician_checkins_excludes_soft_deleted(client, admin_api_key):
    pat_token, cli_token, pat_id = _setup_patient_clinician(client, admin_api_key, suffix="_cc")

    c1 = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat_token)).json()["id"]
    c2 = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat_token)).json()["id"]
    client.delete(f"/v1/checkins/{c1}", headers=_bearer(pat_token))

    resp = client.get(f"/v1/patients/{pat_id}/checkins", headers=_bearer(cli_token))
    assert resp.status_code == 200
    ids = [item["id"] for item in resp.json()]
    assert c1 not in ids
    assert c2 in ids


# ---------------------------------------------------------------------------
# Patient export excludes soft-deleted checkins
# ---------------------------------------------------------------------------

def test_export_excludes_soft_deleted_checkin(client, admin_api_key):
    pat_token = _pat(client, "sd_exp@test.com")
    c1 = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat_token)).json()["id"]
    c2 = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat_token)).json()["id"]
    client.delete(f"/v1/checkins/{c1}", headers=_bearer(pat_token))

    resp = client.get("/v1/me/export", headers=_bearer(pat_token))
    assert resp.status_code == 200
    checkin_ids = [item["id"] for item in resp.json()["checkins"]]
    assert c1 not in checkin_ids
    assert c2 in checkin_ids


# ---------------------------------------------------------------------------
# Audit log records delete_checkin action
# ---------------------------------------------------------------------------

def test_delete_checkin_audit_log(client, admin_api_key):
    pat_token = _pat(client, "sd_audit@test.com")
    checkin_id = client.post("/v1/checkins", json=CHECKIN, headers=_bearer(pat_token)).json()["id"]
    client.delete(f"/v1/checkins/{checkin_id}", headers=_bearer(pat_token))

    resp = client.get("/v1/me/audit-logs", headers=_bearer(pat_token))
    assert resp.status_code == 200
    actions = [entry["action"] for entry in resp.json()]
    assert "delete_checkin" in actions
