# NeuroFlow - Checklist de Producao

## Backend e PostgreSQL

- Criar banco PostgreSQL gerenciado.
- Definir `DATABASE_URL` no provedor de deploy.
- Definir `NEUROFLOW_SECRET_KEY` com segredo longo.
- Definir `NEUROFLOW_FIELD_ENCRYPTION_KEY` com chave Fernet.
- Habilitar HTTPS obrigatorio.
- Rodar backup automatico do banco.
- Configurar logs sem expor dados sensiveis.
- Configurar monitoramento de uptime e erro 5xx.
- Configurar alertas de falha de envio de e-mail/push.
- Testar `/health`, `/clinician/patients`, `/me/export` e `/me/audit-logs` apos deploy.

## Endpoints de producao ja preparados

- `GET /health`: checagem de disponibilidade.
- `GET /clinician/patients`: lista pacientes vinculados ordenados por `risk_score` quando houver dados.
- `GET /caregivers`: lista cuidadores autorizados pelo paciente.
- `POST /caregivers`: cadastra cuidador com consentimento separado.
- `PATCH /caregivers/{id}`: atualiza contato/vinculo/autorizacao do cuidador.
- `DELETE /caregivers/{id}`: remove cuidador autorizado.
- `POST /devices/push-token`: registra token do dispositivo para push.
- `GET /me/audit-logs`: mostra eventos de auditoria do usuario.
- `GET /me/export`: exporta dados do usuario para portabilidade LGPD.
- `DELETE /me/clinical-data?days_older_than=365`: aplica retencao por idade dos dados.
- `DELETE /me`: remove conta e dados do usuario no backend.

## App iOS

- Alterar `BackendAuthClient.baseURL` para a URL publica da API.
- Testar login, cadastro, envio de check-in e dashboard medico contra producao.
- Habilitar capabilities de notificacao se push remoto for usado.

## Push remoto

Lembretes locais ja funcionam no aparelho. Push remoto para medico exige:

- Apple Push Notification service ou Firebase Cloud Messaging.
- Credenciais APNs/FCM no backend.
- Token de dispositivo salvo por usuario.
- Endpoint para registrar device token.
- Worker ou evento que envie push quando alerta alto for criado.
- O backend ja dispara webhook de push para tokens de medicos vinculados quando ha alerta alto, caso `PUSH_WEBHOOK_URL` esteja configurado.

### Payload de webhook preparado

Configure `PUSH_WEBHOOK_URL` apontando para um servico proprio, Firebase Function ou worker que fale com APNs/FCM. O backend envia:

```json
{
  "token": "device-token",
  "notification": {
    "title": "NeuroFlow",
    "body": "Alerta de Paciente: Risco clinico prioritario"
  },
  "data": {
    "event_type": "clinical_alert",
    "patient_id": "123",
    "risk_title": "Risco clinico prioritario"
  },
  "apns": {
    "payload": {
      "aps": {
        "sound": "default",
        "badge": 1
      }
    }
  }
}
```

Para Firebase, o worker pode repassar esse objeto para FCM quase diretamente. Para APNs puro, o worker deve transformar `notification.body` e `data` no payload `aps` aceito pela Apple.

### Fluxo medico/cuidador

- Paciente aceita consentimento geral.
- Paciente ativa compartilhamento com medico e/ou cuidador separadamente.
- Medico vincula paciente por `/clinician/patients`.
- Paciente cadastra cuidadores por `/caregivers`.
- Alertas clinicos e relatorios automaticos sao enviados para medicos vinculados e cuidadores autorizados.
- Cada tentativa de envio grava `NotificationLog`, exportado em `/me/export`.

## E-mail/SMS

- E-mail: configurar `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD` e `ALERT_FROM_EMAIL`.
- SMS: integrar provedor como Twilio/Zenvia/etc. usando `SMS_WEBHOOK_URL` ou SDK proprio.
- Registrar consentimento para notificacoes e canal escolhido.

## Passo a passo minimo para producao

1. Publicar a API em um provedor com HTTPS.
2. Criar PostgreSQL gerenciado e definir `DATABASE_URL`.
3. Definir `NEUROFLOW_SECRET_KEY` e `NEUROFLOW_FIELD_ENCRYPTION_KEY`.
4. Configurar SMTP para alertas por e-mail.
5. Criar worker APNs/FCM e definir `PUSH_WEBHOOK_URL`.
6. Trocar `BackendAuthClient.baseURL` no app para a URL publica.
7. Testar cadastro, login, consentimento, vinculo medico-paciente e cadastro de cuidador.
8. Gerar check-in de alto risco e verificar e-mail/push/logs.
9. Testar exportacao LGPD e exclusao de conta.
10. Ativar monitoramento, backups e politica de incidentes.

## LGPD

- Revisao juridica da politica.
- Termo de uso e politica de privacidade publica.
- Processo de exclusao/exportacao de dados.
- RIPD/DPIA para dados sensiveis.
- Contratos com operadores/suboperadores.
- Testar exportacao de dados em `/me/export`.
- Testar exclusao/retencao em `/me/clinical-data` e `/me`.
- Definir prazo oficial de retencao por contrato/termo.
- Documentar base legal, consentimento, revogacao e resposta a incidente.

## Validacao clinica

- Revisao das regras por profissionais.
- Estudo retrospectivo e prospectivo.
- Medir sensibilidade, especificidade, falsos alertas e tempo ate evento.
- Bloquear uso diagnostico ate validacao formal.
