"""Coverage for the refresh-token rotation flow added in Sprint 8."""
from .conftest import register


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_register_returns_refresh_token(client):
    response = register(client, email="ref@example.com")
    assert response["refresh_token"]
    assert response["access_token"] != response["refresh_token"]


def test_refresh_rotates_token_and_invalidates_old(client):
    initial = register(client, email="rot@example.com")
    first_refresh = initial["refresh_token"]

    rotation = client.post("/auth/refresh", json={"refresh_token": first_refresh})
    assert rotation.status_code == 200
    new_pair = rotation.json()
    assert new_pair["access_token"] != initial["access_token"]
    assert new_pair["refresh_token"] != first_refresh

    # Old refresh token must no longer be honored.
    replay = client.post("/auth/refresh", json={"refresh_token": first_refresh})
    assert replay.status_code == 401


def test_refresh_rejects_unknown_token(client):
    response = client.post("/auth/refresh", json={"refresh_token": "definitely-not-issued"})
    assert response.status_code == 401


def test_logout_revokes_refresh_token(client):
    initial = register(client, email="bye@example.com")
    access = initial["access_token"]
    refresh = initial["refresh_token"]

    logout = client.post(
        "/auth/logout",
        json={"refresh_token": refresh},
        headers=_bearer(access),
    )
    assert logout.status_code == 200

    # Subsequent refresh attempt with the same token fails.
    response = client.post("/auth/refresh", json={"refresh_token": refresh})
    assert response.status_code == 401


def test_logout_only_revokes_own_token(client):
    alice = register(client, email="alice@example.com")
    bob = register(client, email="bob@example.com")

    # Bob tries to revoke Alice's refresh token using his own access token.
    response = client.post(
        "/auth/logout",
        json={"refresh_token": alice["refresh_token"]},
        headers=_bearer(bob["access_token"]),
    )
    # Backend silently no-ops on tokens that don't belong to the caller.
    assert response.status_code == 200

    # Alice's refresh still works.
    rotation = client.post("/auth/refresh", json={"refresh_token": alice["refresh_token"]})
    assert rotation.status_code == 200
