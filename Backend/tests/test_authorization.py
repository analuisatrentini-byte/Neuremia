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
    "journal_entry": "ok day",
}


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_patient_cannot_access_other_patient_checkins(client):
    alice = register(client, email="alice@example.com")
    bob = register(client, email="bob@example.com")
    alice_token = login(client, email="alice@example.com")
    bob_token = login(client, email="bob@example.com")

    # Alice posts a check-in.
    response = client.post("/checkins", json=PATIENT_PAYLOAD, headers=_bearer(alice_token))
    assert response.status_code == 200

    # Bob tries to read Alice's check-ins.
    response = client.get(
        f"/patients/{alice['user']['id']}/checkins",
        headers=_bearer(bob_token),
    )
    assert response.status_code == 403


def test_patient_cannot_use_clinician_invite_endpoint(client):
    register(client, email="solo@example.com")
    token = login(client, email="solo@example.com")
    response = client.post(
        "/clinician/invites",
        json={"patient_email": "anyone@example.com"},
        headers=_bearer(token),
    )
    assert response.status_code == 403


def test_clinician_cannot_view_patient_data_without_link(client, admin_api_key):
    patient = register(client, email="pat@example.com")
    clinician = register(client, email="doc@example.com")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_api_key)
    doc_token = login(client, email="doc@example.com")

    response = client.get(
        f"/patients/{patient['user']['id']}/checkins",
        headers=_bearer(doc_token),
    )
    assert response.status_code == 403


def test_clinician_sees_patient_only_after_invite_accepted(client, admin_api_key):
    patient = register(client, email="pat2@example.com")
    clinician = register(client, email="doc2@example.com")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_api_key)

    pat_token = login(client, email="pat2@example.com")
    doc_token = login(client, email="doc2@example.com")

    # Clinician invites — should NOT create a link by itself.
    invite_response = client.post(
        "/clinician/invites",
        json={"patient_email": "pat2@example.com"},
        headers=_bearer(doc_token),
    )
    assert invite_response.status_code == 200
    invite_id = invite_response.json()["id"]

    # No link yet: clinician cannot read patient data.
    response = client.get(
        f"/patients/{patient['user']['id']}/checkins",
        headers=_bearer(doc_token),
    )
    assert response.status_code == 403

    # Patient accepts.
    accept = client.post(f"/me/invites/{invite_id}/accept", headers=_bearer(pat_token))
    assert accept.status_code == 200, accept.text
    assert accept.json()["status"] == "accepted"

    # Now the clinician can read.
    response = client.get(
        f"/patients/{patient['user']['id']}/checkins",
        headers=_bearer(doc_token),
    )
    assert response.status_code == 200


def test_clinician_role_required_for_clinician_patients_listing(client):
    register(client, email="patient3@example.com")
    token = login(client, email="patient3@example.com")
    response = client.get("/clinician/patients", headers=_bearer(token))
    assert response.status_code == 403


def test_patient_invites_endpoint_only_for_patients(client, admin_api_key):
    clinician = register(client, email="doc3@example.com")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_api_key)
    token = login(client, email="doc3@example.com")

    response = client.get("/me/invites", headers=_bearer(token))
    assert response.status_code == 403
