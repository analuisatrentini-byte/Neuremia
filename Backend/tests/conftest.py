"""Shared fixtures for the NeuroFlow backend test suite.

Each test gets a fresh on-disk SQLite database under tmp_path and a TestClient
wired to an isolated session. Required env vars are stamped before
`app.security` is imported so the fail-closed validation accepts test keys.
"""
import os
import secrets
from pathlib import Path
from typing import Iterator

import pytest


def _stamp_test_env() -> None:
    os.environ.setdefault("NEUROFLOW_ENV", "test")
    os.environ.setdefault("NEUROFLOW_SECRET_KEY", "test-" + secrets.token_urlsafe(32))
    os.environ.setdefault("NEUROFLOW_ADMIN_API_KEY", "test-admin-" + secrets.token_urlsafe(16))
    # Field encryption key: use a deterministic Fernet key for test isolation.
    os.environ.setdefault(
        "NEUROFLOW_FIELD_ENCRYPTION_KEY",
        "qBJ2VkpKMxFhMQXfYrt3VRPUe6Cz2cQ2Si2dXJI4i3M=",
    )
    # Allow tests to operate without tripping the slowapi rate limits added
    # in Sprint 13.
    os.environ.setdefault("NEUROFLOW_ALLOWED_ORIGINS", "*")
    os.environ.setdefault("NEUROFLOW_ALLOWED_HOSTS", "*")


_stamp_test_env()


@pytest.fixture
def db_url(tmp_path: Path) -> str:
    return f"sqlite:///{tmp_path}/test.db"


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch, db_url: str) -> Iterator:
    monkeypatch.setenv("DATABASE_URL", db_url)

    # Import lazily so the DATABASE_URL above is picked up by app.database.
    from sqlalchemy import create_engine, event
    from sqlalchemy.orm import sessionmaker

    import app.database as database
    import app.main as main
    from app.database import Base

    # Rebuild the engine for the isolated DB and patch the module globals so
    # any caller that resolved them previously still works.
    engine = create_engine(db_url, connect_args={"check_same_thread": False})

    # SQLite does not honor foreign keys (CASCADE / SET NULL) unless this
    # pragma is explicitly turned on every new connection. Mirrors Postgres
    # behavior so the CASCADE-driven delete_my_account path (Sprint 15) is
    # actually exercised by the test suite.
    @event.listens_for(engine, "connect")
    def _enable_fk_pragma(dbapi_connection, _record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys = ON")
        cursor.close()

    TestingSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    monkeypatch.setattr(database, "engine", engine, raising=True)
    monkeypatch.setattr(database, "SessionLocal", TestingSession, raising=True)

    # Create tables straight from metadata so the suite is not coupled to a
    # specific Alembic revision.
    import app.models  # noqa: F401 - ensures all tables register on Base.metadata

    Base.metadata.create_all(bind=engine)

    def _override_get_db():
        session = TestingSession()
        try:
            yield session
        finally:
            session.close()

    main.app.dependency_overrides[database.get_db] = _override_get_db

    from fastapi.testclient import TestClient

    with TestClient(main.app) as test_client:
        yield test_client

    main.app.dependency_overrides.clear()


@pytest.fixture
def admin_api_key() -> str:
    return os.environ["NEUROFLOW_ADMIN_API_KEY"]


# ---- registration / login helpers -------------------------------------------

def register(client, *, email: str, password: str = "supersecret1", full_name: str = "User") -> dict:
    response = client.post(
        "/auth/register",
        json={"email": email, "password": password, "full_name": full_name},
    )
    assert response.status_code == 200, response.text
    return response.json()


def login(client, *, email: str, password: str = "supersecret1") -> str:
    response = client.post("/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def promote_to_clinician(client, *, user_id: int, admin_key: str) -> None:
    response = client.post(
        f"/admin/users/{user_id}/role",
        json={"role": "clinician"},
        headers={"X-Admin-API-Key": admin_key},
    )
    assert response.status_code == 200, response.text
