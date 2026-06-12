from .conftest import login, register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


CAREGIVER = {
    "name": "Mãe",
    "contact": "mae@example.com",
    "relationship": "Mãe",
    "share_enabled": True,
}


def test_create_then_list_caregiver(client):
    register(client, email="care@example.com")
    token = login(client, email="care@example.com")

    create = client.post("/caregivers", json=CAREGIVER, headers=_bearer(token))
    assert create.status_code == 200
    assert create.json()["share_enabled"] is True

    listing = client.get("/caregivers", headers=_bearer(token))
    assert listing.status_code == 200
    assert len(listing.json()) == 1
    assert listing.json()[0]["name"] == "Mãe"


def test_update_caregiver_toggles_share(client):
    register(client, email="care2@example.com")
    token = login(client, email="care2@example.com")
    create = client.post("/caregivers", json=CAREGIVER, headers=_bearer(token))
    caregiver_id = create.json()["id"]

    payload = {**CAREGIVER, "share_enabled": False, "relationship": "Mãe (revogada)"}
    update = client.patch(f"/caregivers/{caregiver_id}", json=payload, headers=_bearer(token))
    assert update.status_code == 200
    assert update.json()["share_enabled"] is False
    assert update.json()["relationship"] == "Mãe (revogada)"


def test_delete_caregiver_removes_record(client):
    register(client, email="care3@example.com")
    token = login(client, email="care3@example.com")
    create = client.post("/caregivers", json=CAREGIVER, headers=_bearer(token))
    caregiver_id = create.json()["id"]

    delete = client.delete(f"/caregivers/{caregiver_id}", headers=_bearer(token))
    assert delete.status_code == 200

    listing = client.get("/caregivers", headers=_bearer(token))
    assert listing.json() == []


def test_caregivers_isolated_per_patient(client):
    register(client, email="alice2@example.com")
    register(client, email="bob2@example.com")
    alice_token = login(client, email="alice2@example.com")
    bob_token = login(client, email="bob2@example.com")

    client.post("/caregivers", json=CAREGIVER, headers=_bearer(alice_token))
    bob_list = client.get("/caregivers", headers=_bearer(bob_token))
    assert bob_list.status_code == 200
    assert bob_list.json() == []


def test_update_caregiver_404_for_other_patient(client):
    register(client, email="own@example.com")
    register(client, email="other@example.com")
    own_token = login(client, email="own@example.com")
    other_token = login(client, email="other@example.com")

    create = client.post("/caregivers", json=CAREGIVER, headers=_bearer(own_token))
    caregiver_id = create.json()["id"]

    response = client.patch(
        f"/caregivers/{caregiver_id}",
        json=CAREGIVER,
        headers=_bearer(other_token),
    )
    assert response.status_code == 404
