"""Regression tests for PHI masking in the notification layer."""
import json
from unittest.mock import MagicMock, patch

from app.notifications import (
    GENERIC_ALERT_BODY,
    GENERIC_ALERT_SUBJECT,
    GENERIC_CRITICAL_ALERT_BODY,
    GENERIC_REPORT_BODY,
    GENERIC_REPORT_SUBJECT,
    NotificationService,
)


def _make_service() -> NotificationService:
    service = NotificationService()
    service.smtp_host = "smtp.test"
    service.smtp_user = "alerts@test"
    service.smtp_password = "secret"
    service.sender = "alerts@test"
    service.push_webhook_url = "https://push.test/send"
    service.sms_webhook_url = "https://sms.test/send"
    return service


def test_clinical_alert_email_does_not_include_patient_name():
    service = _make_service()
    smtp_mock = MagicMock()
    with patch("app.notifications.smtplib.SMTP") as smtp_factory:
        smtp_factory.return_value.__enter__.return_value = smtp_mock
        ok = service.send_clinical_alert_email(
            recipient="doc@test.com",
            patient_name="Ana Silva",
            title="Risco clinico prioritario",
            message="Texto sensivel sobre ideacao",
        )
    assert ok

    sent_message = smtp_mock.send_message.call_args.args[0]
    rendered_body = sent_message.get_content()
    rendered_subject = sent_message["Subject"]

    # PHI fields must NOT leak into SMTP.
    assert "Ana Silva" not in rendered_body
    assert "Risco clinico prioritario" not in rendered_body
    assert "ideacao" not in rendered_body
    # The generic placeholder is what actually goes out.
    assert rendered_subject == GENERIC_ALERT_SUBJECT
    assert GENERIC_ALERT_BODY in rendered_body


def test_clinical_report_email_uses_generic_body():
    service = _make_service()
    smtp_mock = MagicMock()
    with patch("app.notifications.smtplib.SMTP") as smtp_factory:
        smtp_factory.return_value.__enter__.return_value = smtp_mock
        ok = service.send_clinical_report_email(
            recipient="doc@test.com",
            patient_name="Carlos Souza",
            summary="Sumario com humor=2 e adesao baixa.",
        )
    assert ok

    sent_message = smtp_mock.send_message.call_args.args[0]
    body = sent_message.get_content()
    assert "Carlos Souza" not in body
    assert "humor" not in body
    assert sent_message["Subject"] == GENERIC_REPORT_SUBJECT
    assert GENERIC_REPORT_BODY in body


def test_push_webhook_strips_phi_from_payload():
    service = _make_service()
    captured_payload = {}

    class _FakeResponse:
        status = 200

        def __enter__(self_inner):
            return self_inner

        def __exit__(self_inner, *_):
            return False

    def _fake_urlopen(req, timeout):
        captured_payload["body"] = req.data
        return _FakeResponse()

    with patch("app.notifications.request.urlopen", side_effect=_fake_urlopen):
        ok = service.send_push_webhook(
            token="device-token",
            title="Alerta de Ana: ideacao",
            body="Risco alto detectado em diario",
            data={
                "event_type": "clinical_alert",
                "patient_id": "42",
                "risk_title": "Risco alto",
            },
        )
    assert ok

    payload = json.loads(captured_payload["body"])
    assert payload["notification"]["title"] == "Neuremia"
    # Body must not contain the patient name or alert text the caller passed in.
    assert "Ana" not in payload["notification"]["body"]
    assert "ideacao" not in payload["notification"]["body"]
    assert "Risco alto" not in payload["notification"]["body"]

    # Only allowlisted data fields survive; PHI-ish ones are dropped.
    assert payload["data"] == {"event_type": "clinical_alert", "patient_id": "42"}


def test_critical_push_sets_apns_critical_payload_without_phi():
    service = _make_service()
    captured_payload = {}

    class _FakeResponse:
        status = 200

        def __enter__(self_inner):
            return self_inner

        def __exit__(self_inner, *_):
            return False

    def _fake_urlopen(req, timeout):
        captured_payload["body"] = req.data
        return _FakeResponse()

    with patch("app.notifications.request.urlopen", side_effect=_fake_urlopen):
        ok = service.send_push_webhook(
            token="device-token",
            title="Alerta de Ana",
            body="Ideacao suicida positiva",
            data={"event_type": "psychiatric_emergency", "patient_id": "42"},
            critical=True,
        )
    assert ok

    payload = json.loads(captured_payload["body"])
    aps = payload["apns"]["payload"]["aps"]
    assert aps["interruption-level"] == "critical"
    assert aps["sound"]["critical"] == 1
    assert "Ana" not in payload["notification"]["body"]
    assert "Ideacao" not in payload["notification"]["body"]
    assert payload["data"] == {"event_type": "psychiatric_emergency", "patient_id": "42"}


def test_sms_webhook_uses_generic_body_without_phi():
    service = _make_service()
    captured_payload = {}

    class _FakeResponse:
        status = 200

        def __enter__(self_inner):
            return self_inner

        def __exit__(self_inner, *_):
            return False

    def _fake_urlopen(req, timeout):
        captured_payload["body"] = req.data
        return _FakeResponse()

    with patch("app.notifications.request.urlopen", side_effect=_fake_urlopen):
        ok = service.send_sms_webhook(
            recipient="+5511999999999",
            title="Alerta de Ana",
            message="Ideacao suicida positiva",
            data={
                "event_type": "psychiatric_emergency",
                "patient_id": "42",
                "risk_title": "Alto",
            },
        )
    assert ok

    payload = json.loads(captured_payload["body"])
    assert payload["recipient"] == "+5511999999999"
    assert payload["body"] == GENERIC_CRITICAL_ALERT_BODY
    assert "Ana" not in payload["body"]
    assert "Ideacao" not in payload["body"]
    assert payload["data"] == {"event_type": "psychiatric_emergency", "patient_id": "42"}
