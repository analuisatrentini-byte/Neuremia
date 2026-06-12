from .conftest import login, promote_to_clinician, register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _setup_clinician_and_patient(client, admin_api_key):
    patient = register(client, email="invitee@example.com", full_name="Invitee")
    clinician = register(client, email="inviter@example.com", full_name="Doctor")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_api_key)
    pat_token = login(client, email="invitee@example.com")
    doc_token = login(client, email="inviter@example.com")
    return patient, clinician, pat_token, doc_token


def test_invite_creates_pending_status(client, admin_api_key):
    _, _, pat_token, doc_token = _setup_clinician_and_patient(client, admin_api_key)

    response = client.post(
        "/clinician/invites",
        json={"patient_email": "invitee@example.com"},
        headers=_bearer(doc_token),
    )
    assert response.status_code == 200
    assert response.json()["status"] == "pending"

    pending = client.get("/me/invites", headers=_bearer(pat_token))
    assert pending.status_code == 200
    assert len(pending.json()) == 1
    assert pending.json()[0]["clinician_full_name"] == "Doctor"


def test_invite_idempotent_for_same_pair(client, admin_api_key):
    _, _, _, doc_token = _setup_clinician_and_patient(client, admin_api_key)

    first = client.post(
        "/clinician/invites",
        json={"patient_email": "invitee@example.com"},
        headers=_bearer(doc_token),
    )
    second = client.post(
        "/clinician/invites",
        json={"patient_email": "invitee@example.com"},
        headers=_bearer(doc_token),
    )
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["id"] == second.json()["id"]


def test_invite_404_for_unknown_patient(client, admin_api_key):
    _, _, _, doc_token = _setup_clinician_and_patient(client, admin_api_key)
    response = client.post(
        "/clinician/invites",
        json={"patient_email": "nobody@example.com"},
        headers=_bearer(doc_token),
    )
    assert response.status_code == 404


def test_revoke_removes_link_and_sets_revoked_status(client, admin_api_key):
    patient, _, pat_token, doc_token = _setup_clinician_and_patient(client, admin_api_key)

    invite = client.post(
        "/clinician/invites",
        json={"patient_email": "invitee@example.com"},
        headers=_bearer(doc_token),
    )
    invite_id = invite.json()["id"]

    # Patient accepts then revokes.
    accept = client.post(f"/me/invites/{invite_id}/accept", headers=_bearer(pat_token))
    assert accept.status_code == 200

    revoke = client.post(f"/me/invites/{invite_id}/revoke", headers=_bearer(pat_token))
    assert revoke.status_code == 200
    assert revoke.json()["status"] == "revoked"

    # Clinician loses access.
    response = client.get(
        f"/patients/{patient['user']['id']}/checkins",
        headers=_bearer(doc_token),
    )
    assert response.status_code == 403


def test_revoke_404_for_other_patient_invite(client, admin_api_key):
    _, _, _, doc_token = _setup_clinician_and_patient(client, admin_api_key)
    register(client, email="bystander@example.com")
    bystander_token = login(client, email="bystander@example.com")

    invite = client.post(
        "/clinician/invites",
        json={"patient_email": "invitee@example.com"},
        headers=_bearer(doc_token),
    )
    invite_id = invite.json()["id"]

    # Random patient tries to revoke someone else's invite.
    response = client.post(
        f"/me/invites/{invite_id}/revoke",
        headers=_bearer(bystander_token),
    )
    assert response.status_code == 404
