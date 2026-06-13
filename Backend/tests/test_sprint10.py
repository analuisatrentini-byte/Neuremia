"""Regression suite for Sprint 10 surgical fixes.

Covers:
- B41: migration 0003 nullable already verified by other tests.
- D18: admin purge of refresh tokens.
- FN22: re-issuing an invite after the patient revoked it.
- FN19: patient revoking access from an already-linked clinician.
"""
from datetime import datetime, timedelta, timezone

from .conftest import login, promote_to_clinician, register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---------------- D18 ----------------

def test_admin_purge_removes_expired_refresh_tokens(client, admin_api_key):
    from app import database, models

    user = register(client, email="purge@example.com")
    refresh = user["refresh_token"]

    # Backdate one refresh token so it qualifies as expired.
    with database.SessionLocal() as session:
        record = session.query(models.RefreshToken).first()
        record.expires_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=1)
        session.commit()

    response = client.post(
        "/v1/admin/refresh-tokens/purge",
        headers={"X-Admin-API-Key": admin_api_key},
    )
    assert response.status_code == 200
    assert response.json()["deleted_refresh_tokens"] >= 1

    # The expired token can no longer be exchanged.
    rotation = client.post("/v1/auth/refresh", json={"refresh_token": refresh})
    assert rotation.status_code == 401


def test_admin_purge_requires_admin_key(client):
    response = client.post("/v1/admin/refresh-tokens/purge", headers={"X-Admin-API-Key": "wrong"})
    assert response.status_code == 401


def test_admin_purge_drops_old_revoked_tokens(client, admin_api_key):
    """Sprint 11: revoked rows older than 1 day must also be reaped so the
    table doesn't bloat with logged-out sessions."""
    from app import database, models

    register(client, email="reaper@example.com")

    with database.SessionLocal() as session:
        token = session.query(models.RefreshToken).first()
        token.revoked_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=2)
        session.commit()

    response = client.post(
        "/v1/admin/refresh-tokens/purge",
        headers={"X-Admin-API-Key": admin_api_key},
    )
    assert response.status_code == 200
    assert response.json()["deleted_refresh_tokens"] >= 1


def test_admin_purge_skips_fresh_revoked_tokens(client, admin_api_key):
    """Recently revoked rows (less than 24h) stay so they keep showing up
    in audit windows."""
    from app import database, models

    register(client, email="recent-revoke@example.com")

    with database.SessionLocal() as session:
        token = session.query(models.RefreshToken).first()
        token.revoked_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(minutes=10)
        session.commit()

    response = client.post(
        "/v1/admin/refresh-tokens/purge",
        headers={"X-Admin-API-Key": admin_api_key},
    )
    assert response.status_code == 200
    # The fresh-revoked token survives; only old/expired ones are reaped.
    assert response.json()["deleted_refresh_tokens"] == 0


# ---------------- FN22 ----------------

def test_invite_reissue_after_revocation(client, admin_api_key):
    patient = register(client, email="reissue-pat@example.com")
    clinician = register(client, email="reissue-doc@example.com")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_api_key)

    pat_token = login(client, email="reissue-pat@example.com")
    doc_token = login(client, email="reissue-doc@example.com")

    first = client.post(
        "/v1/clinician/invites",
        json={"patient_email": "reissue-pat@example.com"},
        headers=_bearer(doc_token),
    )
    invite_id = first.json()["id"]

    # Patient accepts then revokes.
    client.post(f"/v1/me/invites/{invite_id}/accept", headers=_bearer(pat_token))
    client.post(f"/v1/me/invites/{invite_id}/revoke", headers=_bearer(pat_token))

    # Clinician resends the invite. Should create a fresh pending row, not
    # return the historical revoked one.
    second = client.post(
        "/v1/clinician/invites",
        json={"patient_email": "reissue-pat@example.com"},
        headers=_bearer(doc_token),
    )
    assert second.status_code == 200
    body = second.json()
    assert body["status"] == "pending"
    assert body["id"] != invite_id


# ---------------- FN19 ----------------

def _setup_linked_pair(client, admin_api_key):
    patient = register(client, email="linked-pat@example.com")
    clinician = register(client, email="linked-doc@example.com")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_api_key)
    pat_token = login(client, email="linked-pat@example.com")
    doc_token = login(client, email="linked-doc@example.com")

    invite = client.post(
        "/v1/clinician/invites",
        json={"patient_email": "linked-pat@example.com"},
        headers=_bearer(doc_token),
    )
    invite_id = invite.json()["id"]
    client.post(f"/v1/me/invites/{invite_id}/accept", headers=_bearer(pat_token))
    return patient, clinician, pat_token, doc_token


def test_list_linked_clinicians_shows_accepted_only(client, admin_api_key):
    _, clinician, pat_token, _ = _setup_linked_pair(client, admin_api_key)
    response = client.get("/v1/me/linked-clinicians", headers=_bearer(pat_token))
    assert response.status_code == 200
    body = response.json()
    assert len(body) == 1
    assert body[0]["clinician_id"] == clinician["user"]["id"]
    assert body[0]["clinician_full_name"] == "User"  # default in conftest


def test_revoke_clinical_access_removes_link_and_blocks_doc(client, admin_api_key):
    patient, clinician, pat_token, doc_token = _setup_linked_pair(client, admin_api_key)

    response = client.delete(
        f"/v1/me/clinical-access/{clinician['user']['id']}",
        headers=_bearer(pat_token),
    )
    assert response.status_code == 200

    # Clinician loses access immediately. Token epoch is incremented on revoke,
    # so the existing JWT is invalidated (401); a freshly-issued token would
    # get 403. Either means access is denied.
    forbidden = client.get(
        f"/v1/patients/{patient['user']['id']}/checkins",
        headers=_bearer(doc_token),
    )
    assert forbidden.status_code in (401, 403)

    # Patient's list of linked clinicians is empty.
    listing = client.get("/v1/me/linked-clinicians", headers=_bearer(pat_token))
    assert listing.json() == []

    # The clinician's view of sent invites surfaces revoked status (Sprint 9).
    # Re-login: token_epoch was incremented on revoke, so old JWT is invalid.
    fresh_doc_token = login(client, email="linked-doc@example.com")
    sent = client.get("/v1/clinician/invites", headers=_bearer(fresh_doc_token)).json()
    assert any(item["status"] == "revoked" for item in sent)


def test_revoke_clinical_access_404_if_not_linked(client, admin_api_key):
    register(client, email="solo@example.com")
    register(client, email="ghost-doc@example.com")
    promote_to_clinician(client, user_id=2, admin_key=admin_api_key)
    solo_token = login(client, email="solo@example.com")

    response = client.delete("/v1/me/clinical-access/2", headers=_bearer(solo_token))
    assert response.status_code == 404


def test_linked_clinicians_endpoint_403_for_clinicians(client, admin_api_key):
    register(client, email="doc-only@example.com")
    promote_to_clinician(client, user_id=1, admin_key=admin_api_key)
    token = login(client, email="doc-only@example.com")

    response = client.get("/v1/me/linked-clinicians", headers=_bearer(token))
    assert response.status_code == 403
