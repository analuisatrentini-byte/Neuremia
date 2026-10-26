"""Notification adapters for SMTP and a push-webhook bridge.

Bodies are deliberately generic: they never contain the patient's name,
the alert title, the clinical summary, or any other PHI text. Receivers
are expected to open the Neuremia app to fetch the actual content, where
the data is fetched over the authenticated, encrypted backend channel.
"""
import os
import smtplib
import json
import time
from email.message import EmailMessage
from urllib import request
from urllib.parse import urlparse

_SMTP_MAX_ATTEMPTS = 3
_SMTP_RETRY_BACKOFF_BASE = 1.0  # seconds; doubles on each retry

_PUSH_MAX_ATTEMPTS = 3
_PUSH_RETRY_BACKOFF_BASE = 2.0  # seconds; doubles each retry: 2s, 4s, 8s
# Circuit breaker: after this many consecutive failures, skip calls for
# _PUSH_CIRCUIT_RESET_SECONDS to avoid stacking timeouts under load.
_PUSH_CIRCUIT_THRESHOLD = 5
_PUSH_CIRCUIT_RESET_SECONDS = 60


GENERIC_ALERT_SUBJECT = "Neuremia: nova atualizacao clinica"
GENERIC_ALERT_BODY = (
    "Ha informacao clinica nova vinculada a um paciente sob seu acompanhamento. "
    "Abra o aplicativo Neuremia para revisar com seguranca. "
    "Este e-mail nao contem dados sensiveis."
)
GENERIC_CRITICAL_ALERT_BODY = (
    "Ha uma atualizacao clinica urgente no Neuremia. "
    "Abra o app para revisar com seguranca. "
    "Esta mensagem nao contem dados sensiveis."
)

GENERIC_REPORT_SUBJECT = "Neuremia: novo relatorio para revisao"
GENERIC_REPORT_BODY = (
    "Um novo relatorio clinico esta disponivel para um paciente sob seu cuidado. "
    "Abra o aplicativo Neuremia para revisar com seguranca. "
    "Este e-mail nao contem dados sensiveis."
)


class NotificationService:
    def __init__(self) -> None:
        self.smtp_host = os.getenv("SMTP_HOST", "")
        self.smtp_port = int(os.getenv("SMTP_PORT", "587"))
        self.smtp_user = os.getenv("SMTP_USER", "")
        self.smtp_password = os.getenv("SMTP_PASSWORD", "")
        self.sender = os.getenv("ALERT_FROM_EMAIL", self.smtp_user)
        self.sms_webhook_url = self._validated_webhook_url(
            os.getenv("SMS_WEBHOOK_URL", "")
        )
        # Circuit breaker state for push webhook
        self._push_consecutive_failures = 0
        self._push_circuit_open_until = 0.0
        self.push_webhook_url = self._validated_webhook_url(
            os.getenv("PUSH_WEBHOOK_URL", "")
        )

    @staticmethod
    def _validated_webhook_url(raw: str) -> str:
        """Sprint B: rejeita scheme não-https no PUSH_WEBHOOK_URL para evitar
        SSRF (`file:///etc/passwd`, `http://internal-svc`, etc). Em dev permite
        http://localhost para o mock server local."""
        if not raw:
            return ""
        parsed = urlparse(raw)
        if parsed.scheme == "https":
            return raw
        if parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"}:
            return raw
        # Schemes não permitidos: file, ftp, gopher, etc, e http em hosts não-locais.
        return ""

    @property
    def email_enabled(self) -> bool:
        return bool(self.smtp_host and self.smtp_user and self.smtp_password and self.sender)

    def _send_generic_email(self, recipient: str, subject: str, body: str) -> bool:
        if not self.email_enabled:
            return False

        email = EmailMessage()
        email["From"] = self.sender
        email["To"] = recipient
        email["Subject"] = subject
        email.set_content(body)

        last_exc: Exception | None = None
        for attempt in range(_SMTP_MAX_ATTEMPTS):
            try:
                with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
                    server.starttls()
                    server.login(self.smtp_user, self.smtp_password)
                    server.send_message(email)
                return True
            except (smtplib.SMTPException, OSError) as exc:
                last_exc = exc
                if attempt < _SMTP_MAX_ATTEMPTS - 1:
                    time.sleep(_SMTP_RETRY_BACKOFF_BASE * (2 ** attempt))

        raise last_exc  # type: ignore[misc]

    def send_clinical_alert_email(
        self,
        recipient: str,
        patient_name: str,
        title: str,
        message: str,
    ) -> bool:
        """Patient name, title and message are accepted for API compatibility
        but NEVER forwarded to the SMTP body. SMTP is treated as an
        adversarial channel for PHI."""
        del patient_name, title, message  # explicit: not used in body
        return self._send_generic_email(recipient, GENERIC_ALERT_SUBJECT, GENERIC_ALERT_BODY)

    def send_password_reset_email(self, recipient: str, reset_code: str) -> bool:
        # Password reset code is the only PHI-free, action-specific value we
        # let through SMTP. The reset endpoint validates it server-side.
        return self._send_generic_email(
            recipient,
            "Neuremia: recuperacao de senha",
            "\n".join([
                "Recebemos uma solicitacao de recuperacao de senha.",
                "",
                f"Codigo temporario: {reset_code}",
                "",
                "Se voce nao pediu isso, ignore este e-mail.",
            ]),
        )

    def send_clinical_report_email(
        self,
        recipient: str,
        patient_name: str,
        summary: str,
    ) -> bool:
        del patient_name, summary  # explicit: never inlined in SMTP body
        return self._send_generic_email(recipient, GENERIC_REPORT_SUBJECT, GENERIC_REPORT_BODY)

    def send_push_webhook(
        self,
        token: str,
        title: str,
        body: str,
        data: dict | None = None,
        critical: bool = False,
    ) -> bool:
        """Push notifications go through a generic worker (Firebase/APNs).
        We can't trust that worker to be a HIPAA/LGPD business associate, so
        title/body are replaced with generic strings. Patient identifiers in
        `data` are kept as opaque integers to allow the app to route, but
        names, titles and summaries are stripped."""
        del title, body  # explicit: replaced with generic payload below

        if not self.push_webhook_url:
            return False

        safe_data = {
            k: v for k, v in (data or {}).items()
            if k in {"event_type", "patient_id"}
        }

        aps: dict = {
            "sound": "default",
            "badge": 1,
        }
        if critical:
            aps = {
                "interruption-level": "critical",
                "sound": {
                    "critical": 1,
                    "name": "default",
                    "volume": 1.0,
                },
                "badge": 1,
            }

        payload = json.dumps({
            "token": token,
            "notification": {
                "title": "Neuremia",
                "body": (
                    "Atualizacao clinica urgente. Abra o app para detalhes."
                    if critical else
                    "Nova atualizacao clinica disponivel. Abra o app para detalhes."
                ),
            },
            "data": safe_data,
            "apns": {
                "payload": {
                    "aps": aps,
                }
            },
        }).encode("utf-8")
        # Circuit breaker: fast-fail while circuit is open.
        if time.monotonic() < self._push_circuit_open_until:
            return False

        req = request.Request(
            self.push_webhook_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        for attempt in range(_PUSH_MAX_ATTEMPTS):
            try:
                with request.urlopen(req, timeout=5) as response:
                    success = 200 <= response.status < 300
                if success:
                    self._push_consecutive_failures = 0
                    return True
            except Exception:
                pass
            if attempt < _PUSH_MAX_ATTEMPTS - 1:
                time.sleep(_PUSH_RETRY_BACKOFF_BASE * (2 ** attempt))

        self._push_consecutive_failures += 1
        if self._push_consecutive_failures >= _PUSH_CIRCUIT_THRESHOLD:
            self._push_circuit_open_until = time.monotonic() + _PUSH_CIRCUIT_RESET_SECONDS
            self._push_consecutive_failures = 0
        return False

    def send_sms_webhook(
        self,
        recipient: str,
        title: str,
        message: str,
        data: dict | None = None,
    ) -> bool:
        """Optional SMS bridge for emergencies. Title/message are accepted for
        API compatibility but never sent, because SMS is not a PHI-safe channel."""
        del title, message
        if not self.sms_webhook_url:
            return False

        safe_data = {
            k: v for k, v in (data or {}).items()
            if k in {"event_type", "patient_id"}
        }
        payload = json.dumps({
            "recipient": recipient,
            "body": GENERIC_CRITICAL_ALERT_BODY,
            "data": safe_data,
        }).encode("utf-8")

        req = request.Request(
            self.sms_webhook_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with request.urlopen(req, timeout=5) as response:
                return 200 <= response.status < 300
        except Exception:
            return False


notifications = NotificationService()
