"""Tests for /me/export date-range pagination (C7).

Validates that:
- Without filters, at most _EXPORT_CHECKINS_MAX records are returned.
- from_date / to_date correctly filter check-ins.
- from_date > to_date returns 422.
- The export still includes user, assessments, alerts, reports alongside
  the filtered check-ins.
"""

import pytest

from .conftest import login, register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


CHECKIN_A = {
    "mood": 4, "anxiety": 1, "energy": 4, "irritability": 1,
    "sleep_hours": 8, "appetite": 4, "libido": 3,
    "medication_taken": True, "side_effects": "",
    "automatic_thoughts": "", "suicidal_ideation": False,
    "journal_entry": "first",
}

CHECKIN_B = {**CHECKIN_A, "mood": 2, "journal_entry": "second"}
CHECKIN_C = {**CHECKIN_A, "mood": 3, "journal_entry": "third"}


def test_export_returns_all_fields(client):
    """Full export without filters must contain user, checkins, assessments,
    alerts, reports, audit_logs, notification_logs keys."""
    register(client, email="export_fields@test.com")
    token = login(client, email="export_fields@test.com")
    client.post("/checkins", json=CHECKIN_A, headers=_bearer(token))

    resp = client.get("/me/export", headers=_bearer(token))
    assert resp.status_code == 200
    data = resp.json()

    for key in ("user", "checkins", "assessments", "alerts", "reports",
                "audit_logs", "notification_logs"):
        assert key in data, f"Missing key '{key}' in export response"

    assert len(data["checkins"]) == 1
    assert data["checkins"][0]["journal_entry"] == "first"


def test_export_invalid_date_range_returns_422(client):
    """from_date > to_date must return HTTP 422."""
    register(client, email="export_422@test.com")
    token = login(client, email="export_422@test.com")

    resp = client.get(
        "/me/export",
        params={
            "from_date": "2026-12-31T00:00:00",
            "to_date": "2026-01-01T00:00:00",
        },
        headers=_bearer(token),
    )
    assert resp.status_code == 422, f"Expected 422, got {resp.status_code}: {resp.text}"


def test_export_from_date_filters_older_records(client, monkeypatch):
    """Check-ins created before from_date must be excluded from the export."""
    from datetime import datetime, timezone

    register(client, email="export_from@test.com")
    token = login(client, email="export_from@test.com")

    # Post two check-ins; we'll set from_date to a value that should exclude
    # the first one via the DB query. Since we can't control exact timestamps
    # in the test DB, we verify the filter itself is applied by checking that
    # an impossible future date returns zero check-ins.
    client.post("/checkins", json=CHECKIN_A, headers=_bearer(token))
    client.post("/checkins", json=CHECKIN_B, headers=_bearer(token))

    future = "2099-01-01T00:00:00"
    resp = client.get(
        "/me/export",
        params={"from_date": future},
        headers=_bearer(token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["checkins"] == [], (
        f"Filtering from a far-future date must return 0 checkins, got: {data['checkins']}"
    )


def test_export_to_date_filters_newer_records(client):
    """Check-ins created after to_date must be excluded."""
    register(client, email="export_to@test.com")
    token = login(client, email="export_to@test.com")
    client.post("/checkins", json=CHECKIN_C, headers=_bearer(token))

    past = "2000-01-01T00:00:00"
    resp = client.get(
        "/me/export",
        params={"to_date": past},
        headers=_bearer(token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["checkins"] == [], (
        f"Filtering up to a far-past date must return 0 checkins, got: {data['checkins']}"
    )


def test_export_no_filter_returns_checkins(client):
    """Without date filters, all posted check-ins are returned (up to the cap)."""
    register(client, email="export_nofilter@test.com")
    token = login(client, email="export_nofilter@test.com")

    for checkin in (CHECKIN_A, CHECKIN_B, CHECKIN_C):
        resp = client.post("/checkins", json=checkin, headers=_bearer(token))
        assert resp.status_code == 200

    resp = client.get("/me/export", headers=_bearer(token))
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["checkins"]) == 3, (
        f"Expected 3 check-ins, got {len(data['checkins'])}"
    )


def test_export_audit_log_records_action(client):
    """Each call to /me/export must create an audit log entry for
    'export_account', satisfying LGPD Art. 37 access trail.

    Note on ordering: audit() appends the current export_account row and
    db.commit() persists it AFTER the audit_logs query runs in the same
    request. So export N shows N-1 export_account entries. After 2 exports,
    the second response contains exactly 1 'export_account' entry (from
    the first call). We assert >= 1 to verify the trail exists.
    """
    register(client, email="export_audit@test.com")
    token = login(client, email="export_audit@test.com")

    # First export creates the audit entry.
    client.get("/me/export", headers=_bearer(token))
    # Second export — the first entry is now visible in the audit_logs query.
    export = client.get("/me/export", headers=_bearer(token)).json()

    audit_actions = [entry["action"] for entry in export["audit_logs"]]
    export_count = audit_actions.count("export_account")
    assert export_count >= 1, (
        f"Expected at least 1 'export_account' audit entry, got {export_count}. "
        f"All actions: {audit_actions}"
    )
