# Admin API Key Rotation — Runbook

**Frequency:** Quarterly (every 3 months), or immediately after any suspected compromise.  
**Estimated downtime:** Zero (hot-swap via environment variable reload).  
**Audience:** On-call engineer, DevOps.

---

## Background

The `NEUROFLOW_ADMIN_API_KEY` environment variable gates all `/admin/*` endpoints
(role promotion, user listing, token revocation). It is a shared secret: any operator
who knows it can perform privileged actions. Rotation limits blast radius if the key
is ever leaked (e.g. in a log, a screenshot, a Slack message).

Current limitation: the key is shared — there is no per-operator identity attached
to audit log entries from admin actions. The audit log records `"admin_<action>"` but
not *which* operator performed it. This runbook mitigates the risk through frequent
rotation; per-operator API keys are tracked in the backlog.

---

## Rotation Steps

### 1. Generate a new key

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Copy the output. Do **not** paste it into chat, email, or any logging system.

### 2. Update the secret in your secrets manager

**AWS Secrets Manager:**
```bash
aws secretsmanager update-secret \
  --secret-id neuroflow/prod/admin-api-key \
  --secret-string "NEW_KEY_HERE"
```

**Docker Compose (local/staging):**
Edit `docker-compose.yml` → `environment.NEUROFLOW_ADMIN_API_KEY` and restart the service.

**Heroku / Railway / Render:**
Update the environment variable in the platform dashboard, then redeploy.

### 3. Reload the application

The key is read at startup from the environment. A rolling restart (zero-downtime)
is sufficient — no schema migration required.

```bash
# Example: Docker Compose
docker compose up -d --no-deps --build app
```

### 4. Verify the new key works

```bash
NEW_KEY="NEW_KEY_HERE"
curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Admin-API-Key: $NEW_KEY" \
  https://api.your-domain.com/admin/users
# Expected: 200
```

### 5. Verify the old key is rejected

```bash
OLD_KEY="OLD_KEY_HERE"
curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Admin-API-Key: $OLD_KEY" \
  https://api.your-domain.com/admin/users
# Expected: 401
```

### 6. Distribute the new key to authorized operators

Use a secrets manager share link (e.g. AWS Secrets Manager console, 1Password item)
**not** plaintext channels like Slack or email. Revoke access for any operators who
no longer need it.

### 7. Record the rotation in the change log

Add a line to `docs/admin_key_rotation_log.md` (create if absent):

```
| Date       | Rotated by | Reason              |
|------------|------------|---------------------|
| YYYY-MM-DD | @handle    | Quarterly rotation  |
```

---

## Emergency Rotation (suspected compromise)

Follow steps 1–6 above immediately. Additionally:

1. Check audit logs for unexpected admin actions in the last 24 hours:
   ```bash
   # Query audit_logs table for admin actions
   SELECT actor_user_id, action, resource_type, resource_id, created_at
   FROM audit_logs
   WHERE action LIKE 'admin_%'
   ORDER BY created_at DESC
   LIMIT 100;
   ```

2. If unauthorized role promotions are found, demote affected users:
   ```bash
   curl -X POST https://api.your-domain.com/admin/users/{id}/role \
     -H "X-Admin-API-Key: $NEW_KEY" \
     -H "Content-Type: application/json" \
     -d '{"role": "patient"}'
   ```

3. Revoke all active sessions for affected users via token epoch increment:
   ```bash
   curl -X POST https://api.your-domain.com/admin/users/{id}/revoke-sessions \
     -H "X-Admin-API-Key: $NEW_KEY"
   ```

4. File an incident report with timestamp, scope, and remediation steps.

---

## Next Steps (backlog)

- **Per-operator API keys**: issue a unique key per operator so audit logs capture
  *who* performed each admin action, not just *that* an admin action occurred.
- **Key expiry**: add an `expires_at` field to admin tokens so rotation is enforced
  automatically rather than relying on calendar reminders.
