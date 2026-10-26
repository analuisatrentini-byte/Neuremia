from datetime import timedelta

import app.database as database
from app import models
from app.services import utcnow
from .conftest import login, register


def _metric(body: dict, name: str) -> dict:
    return next(metric for metric in body["metrics"] if metric["name"] == name)


def test_admin_ops_status_requires_admin_key(client):
    response = client.get("/v1/admin/ops/status", headers={"X-Admin-API-Key": "wrong"})

    assert response.status_code == 401


def test_admin_ops_status_reports_aggregate_production_signals(client, admin_api_key):
    user = register(client, email="ops_patient@test.com", full_name="Ops Patient")
    token = login(client, email="ops_patient@test.com")
    client.post(
        "/v1/devices/push-token",
        json={"token": "apns-token-for-ops-test", "platform": "ios"},
        headers={"Authorization": f"Bearer {token}"},
    )

    session = database.SessionLocal()
    try:
        session.add(models.ClinicalAlert(
            patient_id=user["user"]["id"],
            created_at=utcnow() - timedelta(hours=25),
            level="high",
            alert_type=models.AlertType.psychiatric_emergency.value,
            escalation_target=models.EscalationTarget.clinician_caregiver_now.value,
            title="High risk",
            message="Encrypted PHI placeholder",
            acknowledged=False,
        ))
        session.add(models.NotificationLog(
            patient_id=user["user"]["id"],
            recipient="redacted",
            channel="push",
            event_type="clinical_alert",
            status="failed",
            detail="webhook unavailable",
        ))
        session.commit()
    finally:
        session.close()

    response = client.get(
        "/v1/admin/ops/status",
        headers={"X-Admin-API-Key": admin_api_key},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "degraded"
    assert _metric(body, "accounts")["value"] == 1
    assert _metric(body, "active_sessions")["value"] >= 1
    assert _metric(body, "registered_devices")["status"] == "pass"
    assert _metric(body, "open_high_alerts")["value"] == 1
    assert _metric(body, "stale_high_alerts_24h")["status"] == "fail"
    assert _metric(body, "notification_failures_24h")["status"] == "warn"
    rendered = str(body)
    assert "ops_patient@test.com" not in rendered
    assert "Ops Patient" not in rendered
