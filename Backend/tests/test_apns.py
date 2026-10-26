"""APNs protocol, credential signing, environment routing, and PHI boundaries."""
import json
from unittest.mock import patch

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app.notifications import NotificationService


@pytest.fixture
def service(monkeypatch):
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    for name, value in {"APNS_KEY_ID": "TESTKEY", "APNS_TEAM_ID": "TESTTEAM",
                        "APNS_BUNDLE_ID": "test.app", "APNS_PRIVATE_KEY": pem}.items():
        monkeypatch.setenv(name, value)
    return NotificationService(), key


@pytest.mark.parametrize("platform,host", [("ios", "api.push.apple.com"),
                                          ("ios-sandbox", "api.sandbox.push.apple.com")])
def test_signed_generic_push(service, platform, host):
    sender, key = service
    requests = []

    def respond(req):
        requests.append(req)
        return httpx.Response(200)

    client = httpx.Client(transport=httpx.MockTransport(respond))
    with patch("app.apns.httpx.Client", return_value=client):
        assert sender.send_push_webhook("ab" * 32, "Patient Name", "Sensitive text",
                                            {"event_type": "clinical_alert", "summary": "secret"},
                                            critical=True, platform=platform)
    req = requests[0]
    assert req.url.host == host
    assert req.headers["apns-topic"] == "test.app"
    assert req.headers["apns-push-type"] == "alert"
    token = req.headers["authorization"].split()[1]
    claims = jwt.decode(token, key.public_key(), algorithms=["ES256"], issuer="TESTTEAM")
    assert "iat" in claims
    assert jwt.get_unverified_header(token)["kid"] == "TESTKEY"
    payload = json.loads(req.content)
    assert payload["aps"]["sound"] == "default"
    assert "interruption-level" not in payload["aps"]
    assert payload["data"] == {"event_type": "clinical_alert"}
    assert "Patient Name" not in req.content.decode()
    assert "Sensitive text" not in req.content.decode()
    assert sender.apns._authorization() == "bearer " + token


def test_rejection_is_not_reported_as_delivery(service):
    sender, _ = service
    client = httpx.Client(transport=httpx.MockTransport(lambda req: httpx.Response(410)))
    with patch("app.apns.httpx.Client", return_value=client):
        assert not sender.send_push_webhook("ab" * 32, "", "")


def test_invalid_token_or_platform_never_sends(service):
    sender, _ = service
    with patch("app.apns.httpx.Client") as client:
        assert not sender.send_push_webhook("../bad", "", "")
        assert not sender.send_push_webhook("ab" * 32, "", "", platform="android")
        client.assert_not_called()


def test_missing_config_is_disabled(monkeypatch):
    monkeypatch.delenv("APNS_PRIVATE_KEY", raising=False)
    monkeypatch.delenv("PUSH_WEBHOOK_URL", raising=False)
    assert not NotificationService().send_push_webhook("ab" * 32, "", "")
