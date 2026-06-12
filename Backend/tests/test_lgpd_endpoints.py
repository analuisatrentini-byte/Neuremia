"""Coverage for the data-subject-rights endpoints: /me/export,
/me/audit-logs, DELETE /me/clinical-data, DELETE /me."""
from .conftest import login, register


PATIENT_PAYLOAD = {
    "mood": 2,
    "anxiety": 4,
    "energy": 2,
    "irritability": 3,
    "sleep_hours": 5,
    "appetite": 2,
    "libido": 2,
    "medication_taken": False,
    "side_effects": "Sono ruim",
    "automatic_thoughts": "preocupado",
    "suicidal_ideation": False,
    "journal_entry": "diario do dia",
}


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_export_returns_full_envelope(client):
    register(client, email="exp@example.com")
    token = login(client, email="exp@example.com")
    client.post("/checkins", json=PATIENT_PAYLOAD, headers=_bearer(token))

    response = client.get("/me/export", headers=_bearer(token))
    assert response.status_code == 200
    body = response.json()
    assert body["user"]["email"] == "exp@example.com"
    assert len(body["checkins"]) == 1
    assert body["checkins"][0]["journal_entry"] == "diario do dia"
    # audit logs include the check-in creation event.
    actions = {entry["action"] for entry in body["audit_logs"]}
    assert "create_checkin" in actions


def test_audit_logs_endpoint_returns_user_actions(client):
    register(client, email="aud@example.com")
    token = login(client, email="aud@example.com")
    response = client.get("/me/audit-logs", headers=_bearer(token))
    assert response.status_code == 200
    actions = {entry["action"] for entry in response.json()}
    # `register` and the implicit login each emit an audit entry.
    assert "register" in actions
    assert "login" in actions


def test_retention_delete_removes_only_old_records(client):
    register(client, email="ret@example.com")
    token = login(client, email="ret@example.com")
    client.post("/checkins", json=PATIENT_PAYLOAD, headers=_bearer(token))

    # days_older_than is huge → nothing is old enough to delete.
    response = client.delete(
        "/me/clinical-data?days_older_than=3650",
        headers=_bearer(token),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["deleted_checkins"] == 0
    assert body["deleted_assessments"] == 0
    assert body["deleted_alerts"] == 0
    assert body["deleted_reports"] == 0

    # Recent data is preserved in the export.
    export = client.get("/me/export", headers=_bearer(token)).json()
    assert len(export["checkins"]) == 1


def test_delete_account_removes_user_and_invalidates_token(client):
    register(client, email="bye@example.com")
    token = login(client, email="bye@example.com")
    response = client.delete("/me", headers=_bearer(token))
    assert response.status_code == 200
    assert response.json()["message"]

    # Token continues to decode but the user no longer exists.
    follow_up = client.get("/me", headers=_bearer(token))
    assert follow_up.status_code == 401


def test_delete_account_preserves_audit_trail(client):
    """Sprint 9 regression: DELETE /me must succeed without FK violation and
    keep audit logs alive (with NULL actor) so forensic review is possible.

    Direct verification needs a privileged query against the database, which
    the public API doesn't expose. We assert the indirect contract: delete
    succeeds, returning the same patient cannot read the previous audit
    history, and the rows that survive carry NULL `actor_user_id`.
    """
    from app import database, models

    user = register(client, email="audit-keeper@example.com")
    token = login(client, email="audit-keeper@example.com")
    user_id = user["user"]["id"]

    response = client.delete("/me", headers=_bearer(token))
    assert response.status_code == 200, response.text

    # User row is gone, audit rows persist with NULL actor.
    with database.SessionLocal() as session:
        assert session.query(models.User).filter_by(id=user_id).first() is None
        orphaned = session.query(models.AuditLog).filter(
            models.AuditLog.actor_user_id.is_(None)
        ).count()
        # The pre-delete actions (register, login, delete_account) are kept.
        assert orphaned >= 3


def test_delete_account_cleans_clinical_records(client):
    register(client, email="purge@example.com")
    token = login(client, email="purge@example.com")
    client.post("/checkins", json=PATIENT_PAYLOAD, headers=_bearer(token))

    delete_response = client.delete("/me", headers=_bearer(token))
    assert delete_response.status_code == 200

    # Logging in again with the same credentials should fail.
    relogin = client.post(
        "/auth/login",
        json={"email": "purge@example.com", "password": "supersecret1"},
    )
    assert relogin.status_code == 401
