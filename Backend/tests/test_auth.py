from .conftest import login, register


def test_register_creates_patient_role_only(client):
    """Sprint 1 regression: self-service signup must never produce a clinician
    account, even if the payload tries to inject `role`."""
    response = client.post(
        "/v1/auth/register",
        json={
            "email": "patient@example.com",
            "password": "supersecret1",
            "full_name": "Patient One",
            "role": "clinician",  # attempt to escalate
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["user"]["role"] == "patient"


def test_register_duplicate_email_returns_200_without_revealing_existence(client):
    """Duplicate registration must return 200 with a neutral message, not 400/409.
    Returning an error status leaks that the email is registered — a patient PII
    enumeration risk in a psychiatric app. The response body must not mention
    the duplicate either (covered by test_security_contracts.py::TestUserEnumeration)."""
    register(client, email="dup@example.com")
    response = client.post(
        "/v1/auth/register",
        json={"email": "dup@example.com", "password": "supersecret1", "full_name": "Dup"},
    )
    assert response.status_code == 200
    assert "access_token" not in response.json(), (
        "Duplicate registration must not issue tokens — only a neutral confirmation message"
    )


def test_register_rejects_short_password(client):
    response = client.post(
        "/v1/auth/register",
        json={"email": "short@example.com", "password": "abc", "full_name": "Short"},
    )
    assert response.status_code == 422


def test_login_round_trip_returns_user(client):
    register(client, email="round@example.com", full_name="Round Trip")
    response = client.post(
        "/v1/auth/login",
        json={"email": "round@example.com", "password": "supersecret1"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["user"]["email"] == "round@example.com"
    assert body["user"]["full_name"] == "Round Trip"
    assert body["access_token"]
    assert body["token_type"] == "bearer"


def test_login_rejects_wrong_password(client):
    register(client, email="wrong@example.com")
    response = client.post(
        "/v1/auth/login",
        json={"email": "wrong@example.com", "password": "wrong-password"},
    )
    assert response.status_code == 401


def test_login_rejects_unknown_email(client):
    response = client.post(
        "/v1/auth/login",
        json={"email": "nobody@example.com", "password": "supersecret1"},
    )
    assert response.status_code == 401


def test_me_requires_bearer_token(client):
    response = client.get("/v1/me")
    assert response.status_code == 401


def test_me_returns_authenticated_user(client):
    register(client, email="me@example.com", full_name="Me Me")
    token = login(client, email="me@example.com")
    response = client.get("/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["email"] == "me@example.com"


def test_password_reset_does_not_reveal_existence(client):
    response = client.post("/v1/auth/password-reset", json={"email": "ghost@example.com"})
    assert response.status_code == 200
    assert "instrucoes" in response.json()["message"].lower()


def test_admin_endpoint_requires_api_key(client):
    register(client, email="elevate@example.com")
    response = client.post(
        "/v1/admin/users/1/role",
        json={"role": "clinician"},
        headers={"X-Admin-API-Key": "wrong-key"},
    )
    assert response.status_code == 401


def test_admin_endpoint_promotes_user_with_correct_key(client, admin_api_key):
    user = register(client, email="elev@example.com")
    response = client.post(
        f"/v1/admin/users/{user['user']['id']}/role",
        json={"role": "clinician"},
        headers={"X-Admin-API-Key": admin_api_key},
    )
    assert response.status_code == 200
    assert response.json()["role"] == "clinician"


def test_admin_endpoint_404_for_unknown_user(client, admin_api_key):
    response = client.post(
        "/v1/admin/users/999999/role",
        json={"role": "clinician"},
        headers={"X-Admin-API-Key": admin_api_key},
    )
    assert response.status_code == 404
