"""Direct Apple push delivery. Credentials stay on the server."""
import logging
import os
import re
import threading
import time

import httpx
import jwt

logger = logging.getLogger(__name__)


class APNsSender:
    def __init__(self):
        self.key_id = os.getenv("APNS_KEY_ID", "")
        self.team_id = os.getenv("APNS_TEAM_ID", "")
        self.topic = os.getenv("APNS_BUNDLE_ID", "")
        self.private_key = os.getenv("APNS_PRIVATE_KEY", "").replace("\\n", "\n")
        self._jwt = ""
        self._issued_at = 0
        self._lock = threading.Lock()

    @property
    def enabled(self) -> bool:
        return all((self.key_id, self.team_id, self.topic, self.private_key))

    def _authorization(self) -> str:
        with self._lock:
            now = int(time.time())
            if not self._jwt or now - self._issued_at >= 3000:
                self._jwt = jwt.encode(
                    {"iss": self.team_id, "iat": now}, self.private_key,
                    algorithm="ES256", headers={"kid": self.key_id},
                )
                self._issued_at = now
            return f"bearer {self._jwt}"

    def send(self, token: str, alert: dict, data: dict, platform: str = "ios") -> bool:
        if not self.enabled or platform not in {"ios", "ios-sandbox"}:
            return False
        if not re.fullmatch(r"[0-9a-fA-F]{32,512}", token):
            return False
        host = "api.sandbox.push.apple.com" if platform == "ios-sandbox" else "api.push.apple.com"
        # Urgent clinical events still use ordinary alerts. Critical alerts
        # require a separate Apple entitlement that this app does not have.
        payload = {"aps": {"alert": alert, "sound": "default", "badge": 1}, "data": data}
        try:
            headers = {
                "authorization": self._authorization(), "apns-topic": self.topic,
                "apns-push-type": "alert", "apns-priority": "10",
            }
            with httpx.Client(http2=True, timeout=5) as client:
                response = client.post(f"https://{host}/3/device/{token}", headers=headers, json=payload)
            if response.status_code != 200:
                # Never log the token, key, JWT, or payload.
                logger.warning("APNs rejected notification (HTTP %s)", response.status_code)
            return response.status_code == 200
        except (httpx.HTTPError, ValueError, jwt.PyJWTError):
            logger.warning("APNs delivery failed; check connection and signing configuration")
            return False
