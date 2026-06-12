# NeuroFlow - Checklist de Producao

## Backend e PostgreSQL

- Criar banco PostgreSQL gerenciado.
- Definir `DATABASE_URL` no provedor de deploy.
- Definir `NEUROFLOW_SECRET_KEY` com segredo longo.
- Definir `NEUROFLOW_FIELD_ENCRYPTION_KEY` com chave Fernet.
- Habilitar HTTPS obrigatorio.
- Rodar backup automatico do banco.
- Configurar logs sem expor dados sensiveis.

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

## E-mail/SMS

- E-mail: configurar `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD` e `ALERT_FROM_EMAIL`.
- SMS: integrar provedor como Twilio/Zenvia/etc. usando `SMS_WEBHOOK_URL` ou SDK proprio.
- Registrar consentimento para notificacoes e canal escolhido.

## LGPD

- Revisao juridica da politica.
- Termo de uso e politica de privacidade publica.
- Processo de exclusao/exportacao de dados.
- RIPD/DPIA para dados sensiveis.
- Contratos com operadores/suboperadores.

## Validacao clinica

- Revisao das regras por profissionais.
- Estudo retrospectivo e prospectivo.
- Medir sensibilidade, especificidade, falsos alertas e tempo ate evento.
- Bloquear uso diagnostico ate validacao formal.
