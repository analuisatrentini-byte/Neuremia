from .conftest import grant_consent, login, promote_to_clinician, register


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
    grant_consent(client, token=alice_token)

    # Alice posts a check-in.
    response = client.post("/v1/checkins", json=PATIENT_PAYLOAD, headers=_bearer(alice_token))
    assert response.status_code == 200

    # Bob tries to read Alice's check-ins.
    response = client.get(
        f"/v1/patients/{alice['user']['id']}/checkins",
        headers=_bearer(bob_token),
    )
    assert response.status_code == 403


def test_patient_cannot_use_clinician_invite_endpoint(client):
    register(client, email="solo@example.com")
    token = login(client, email="solo@example.com")
    response = client.post(
        "/v1/clinician/invites",
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
        f"/v1/patients/{patient['user']['id']}/checkins",
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
        "/v1/clinician/invites",
        json={"patient_email": "pat2@example.com"},
        headers=_bearer(doc_token),
    )
    assert invite_response.status_code == 200
    invite_id = invite_response.json()["id"]

    # No link yet: clinician cannot read patient data.
    response = client.get(
        f"/v1/patients/{patient['user']['id']}/checkins",
        headers=_bearer(doc_token),
    )
    assert response.status_code == 403

    # Patient accepts.
    accept = client.post(f"/v1/me/invites/{invite_id}/accept", headers=_bearer(pat_token))
    assert accept.status_code == 200, accept.text
    assert accept.json()["status"] == "accepted"

    # Now the clinician can read.
    response = client.get(
        f"/v1/patients/{patient['user']['id']}/checkins",
        headers=_bearer(doc_token),
    )
    assert response.status_code == 200


def test_clinician_patient_link_requires_accepted_invite(client, admin_api_key):
    patient = register(client, email="orphan-link-patient@example.com")
    clinician = register(client, email="orphan-link-doc@example.com")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_api_key)
    doc_token = login(client, email="orphan-link-doc@example.com")

    from app import models
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        db.add(models.ClinicianPatientLink(
            clinician_id=clinician["user"]["id"],
            patient_id=patient["user"]["id"],
        ))
        db.commit()
    finally:
        db.close()

    response = client.get(
        f"/v1/patients/{patient['user']['id']}/checkins",
        headers=_bearer(doc_token),
    )
    assert response.status_code == 403

    listing = client.get("/v1/clinician/patients", headers=_bearer(doc_token))
    assert listing.status_code == 200
    assert listing.json()["items"] == []

    patient_listing = client.get("/v1/me/linked-clinicians", headers=_bearer(login(client, email="orphan-link-patient@example.com")))
    assert patient_listing.status_code == 200
    assert patient_listing.json() == []


def test_other_clinician_cannot_view_accepted_patient_link(client, admin_api_key):
    patient = register(client, email="specific-patient@example.com")
    linked_doc = register(client, email="linked-doc@example.com")
    other_doc = register(client, email="other-doc@example.com")
    promote_to_clinician(client, user_id=linked_doc["user"]["id"], admin_key=admin_api_key)
    promote_to_clinician(client, user_id=other_doc["user"]["id"], admin_key=admin_api_key)

    pat_token = login(client, email="specific-patient@example.com")
    linked_doc_token = login(client, email="linked-doc@example.com")
    other_doc_token = login(client, email="other-doc@example.com")

    invite = client.post(
        "/v1/clinician/invites",
        json={"patient_email": "specific-patient@example.com"},
        headers=_bearer(linked_doc_token),
    )
    assert invite.status_code == 200
    accept = client.post(f"/v1/me/invites/{invite.json()['id']}/accept", headers=_bearer(pat_token))
    assert accept.status_code == 200

    linked_response = client.get(
        f"/v1/patients/{patient['user']['id']}/checkins",
        headers=_bearer(linked_doc_token),
    )
    assert linked_response.status_code == 200

    other_response = client.get(
        f"/v1/patients/{patient['user']['id']}/checkins",
        headers=_bearer(other_doc_token),
    )
    assert other_response.status_code == 403


def test_clinician_role_required_for_clinician_patients_listing(client):
    register(client, email="patient3@example.com")
    token = login(client, email="patient3@example.com")
    response = client.get("/v1/clinician/patients", headers=_bearer(token))
    assert response.status_code == 403


def test_patient_invites_endpoint_only_for_patients(client, admin_api_key):
    clinician = register(client, email="doc3@example.com")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_api_key)
    token = login(client, email="doc3@example.com")

    response = client.get("/v1/me/invites", headers=_bearer(token))
    assert response.status_code == 403
