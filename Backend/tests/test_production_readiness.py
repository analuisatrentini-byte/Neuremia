from app.main import production_readiness_checks


def _by_name(checks):
    return {check["name"]: check for check in checks}


def test_production_readiness_passes_core_cloud_requirements():
    checks = production_readiness_checks(
        env="production",
        database_url="postgresql+psycopg://user:pass@db:5432/neuremia",
        allowed_hosts=["api.neuremia.example"],
        allowed_origins=["https://app.neuremia.example"],
        secret_key_present=True,
        field_encryption_key_present=True,
        admin_api_key_present=True,
        backup_schedule="daily-managed-snapshot",
        push_webhook_url="https://push.example/notify",
        sms_webhook_url="https://sms.example/send",
    )

    by_name = _by_name(checks)
    assert by_name["database"]["status"] == "pass"
    assert by_name["trusted_hosts"]["status"] == "pass"
    assert by_name["cors"]["status"] == "pass"
    assert by_name["jwt_secret"]["status"] == "pass"
    assert by_name["field_encryption"]["status"] == "pass"
    assert by_name["admin_key"]["status"] == "pass"
    assert by_name["backups"]["status"] == "pass"
    assert by_name["critical_notifications"]["status"] == "pass"


def test_production_readiness_fails_closed_for_unsafe_core_config():
    checks = production_readiness_checks(
        env="production",
        database_url="sqlite:///./neuremia.db",
        allowed_hosts=["*"],
        allowed_origins=[],
        secret_key_present=False,
        field_encryption_key_present=False,
        admin_api_key_present=False,
        backup_schedule="",
        push_webhook_url="",
        sms_webhook_url="",
    )

    by_name = _by_name(checks)
    assert by_name["database"]["status"] == "fail"
    assert by_name["trusted_hosts"]["status"] == "fail"
    assert by_name["cors"]["status"] == "fail"
    assert by_name["jwt_secret"]["status"] == "fail"
    assert by_name["field_encryption"]["status"] == "fail"
    assert by_name["admin_key"]["status"] == "fail"
    assert by_name["backups"]["status"] == "fail"
    assert by_name["critical_notifications"]["status"] == "warn"


def test_development_readiness_allows_local_defaults():
    checks = production_readiness_checks(
        env="development",
        database_url="sqlite:///./neuremia.db",
        allowed_hosts=["*"],
        allowed_origins=[],
        secret_key_present=False,
        field_encryption_key_present=False,
        admin_api_key_present=False,
        backup_schedule="",
        push_webhook_url="",
        sms_webhook_url="",
    )

    assert not [check for check in checks if check["status"] == "fail"]


def test_ready_endpoint_returns_redacted_operational_checks(client):
    response = client.get("/ready")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ready"
    assert body["db"] == "ok"
    assert "checks" in body
    rendered = str(body)
    assert "replace-with" not in rendered
    assert "PASSWORD" not in rendered
