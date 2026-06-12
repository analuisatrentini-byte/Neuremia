# NeuroFlow Backend

API em FastAPI que sustenta autenticação, registros clínicos, vínculo médico-paciente (via convite com aceite), notificações e direitos LGPD do app iOS NeuroFlow.

## Stack

- Python 3.12+ (testado em 3.14)
- FastAPI + SQLAlchemy 2.x + Alembic
- bcrypt (pinado `<4` por compatibilidade com passlib 1.7.x)
- Fernet para criptografia de campos sensíveis em repouso

## Variáveis obrigatórias em produção (`NEUROFLOW_ENV=production`)

| Variável | Como gerar |
|---|---|
| `NEUROFLOW_SECRET_KEY` | `python -c "import secrets; print(secrets.token_urlsafe(64))"` |
| `NEUROFLOW_FIELD_ENCRYPTION_KEY` | `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"` |
| `NEUROFLOW_ADMIN_API_KEY` | `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `DATABASE_URL` | URL Postgres gerenciado, ex. `postgresql+psycopg://user:pass@host:5432/neuroflow` |

Em desenvolvimento (`NEUROFLOW_ENV=development` ou ausente), chaves efêmeras são geradas por boot. Não existem em produção sem fail-fast.

## Rodar localmente

```bash
cd Backend
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Aplica migrations (cria tabelas)
alembic upgrade head

uvicorn app.main:app --reload
```

Abrir `http://127.0.0.1:8000/docs` para o Swagger.

## Banco de dados

Padrão dev: SQLite em `./neuroflow.db`. **Não versionar este arquivo.** O `.gitignore` já cobre.

Trocar para Postgres:

```bash
export DATABASE_URL="postgresql+psycopg://user:pass@localhost:5432/neuroflow"
```

### Migrations (Alembic)

```bash
alembic upgrade head          # aplica todas
alembic downgrade -1          # reverte uma
alembic revision --autogenerate -m "descrever"   # gerar nova migration
alembic stamp head            # marca DB existente como atual (sem rodar SQL)
```

Bootstrap em DB já populado pelo código antigo (`Base.metadata.create_all`): `alembic stamp head`.

## Docker

```bash
cd Backend
cp .env.example .env   # editar as 4 chaves
docker compose up --build
```

O `Dockerfile` roda `alembic upgrade head` antes de iniciar o uvicorn — falha cedo se migration estiver quebrada.

## Testes

```bash
source .venv/bin/activate
pip install pytest httpx
python -m pytest tests/ -q
```

Suite atual: **33 testes**, cobre auth, RBAC, fluxo de convite clínico, endpoints LGPD e CRUD de cuidadores.

## Segurança e conformidade

- Self-service signup cria **sempre** `role=patient`. Promoção para clínico requer `POST /admin/users/{id}/role` com header `X-Admin-API-Key`.
- Vínculo clínico-paciente exige aceite explícito: clínico chama `POST /clinician/invites`; paciente vê em `GET /me/invites` e aceita via `POST /me/invites/{id}/accept`. Revogação: `POST /me/invites/{id}/revoke` (também remove o link).
- Campos sensíveis (`side_effects`, `automatic_thoughts`, `journal_entry`, `clinical_alert.message`, `clinical_report.summary`) são criptografados em repouso via Fernet.
- Senhas com bcrypt + salt automático.
- `AuditLog` registra ações relevantes. Acessível pelo titular em `GET /me/audit-logs`.
- Em produção, `decrypt_field` falha fechado se a chave não bater (não cai em plaintext fallback).

## Endpoints principais

### Autenticação
- `POST /auth/register` — cria conta paciente (role nunca aceito do cliente)
- `POST /auth/login`
- `POST /auth/password-reset`
- `GET /me`

### Direitos LGPD do titular
- `GET /me/audit-logs`
- `GET /me/export` — JSON completo da conta
- `DELETE /me/clinical-data?days_older_than=N` — retenção configurável
- `DELETE /me` — exclusão de conta

### Médico/paciente
- `POST /clinician/invites` (clínico)
- `GET /me/invites` (paciente)
- `POST /me/invites/{id}/accept` (paciente)
- `POST /me/invites/{id}/revoke` (paciente)
- `GET /clinician/patients` — lista vinculados ordenados por risk_score

### Dados clínicos (com isolamento por paciente)
- `POST /checkins`, `GET /patients/{id}/checkins`
- `POST /assessments`, `GET /patients/{id}/assessments`
- `GET /patients/{id}/alerts`
- `POST /reports`, `GET /patients/{id}/reports`

### Cuidadores
- `GET /caregivers`, `POST /caregivers`
- `PATCH /caregivers/{id}`, `DELETE /caregivers/{id}`

### Push
- `POST /devices/push-token`

### Admin
- `POST /admin/users/{id}/role` (X-Admin-API-Key)

## Documentação relacionada

- [`docs/LGPD_POLICY.md`](docs/LGPD_POLICY.md)
- [`docs/CLINICAL_VALIDATION.md`](docs/CLINICAL_VALIDATION.md)
- [`docs/PRODUCTION_READINESS.md`](docs/PRODUCTION_READINESS.md)
- [`docs/THEORETICAL_BASIS_AND_VALIDATION.md`](docs/THEORETICAL_BASIS_AND_VALIDATION.md)
- [`docs/OFFICIAL_SCALES.md`](docs/OFFICIAL_SCALES.md)
