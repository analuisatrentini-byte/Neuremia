# NeuroFlow - Politica LGPD Operacional

Este documento e um ponto de partida tecnico. Antes de uso real com pacientes, deve ser revisado por advogado, encarregado/DPO e equipe clinica.

## Dados tratados

- Identificacao: nome, e-mail, perfil de acesso.
- Dados sensiveis de saude: humor, ansiedade, sono, energia, irritabilidade, apetite, libido, medicacao, efeitos colaterais, escalas, diario, alertas e relatorios.
- Auditoria: usuario, acao, recurso acessado e data/hora.

## Base legal e consentimento

- Coletar consentimento explicito antes de salvar dados clinicos.
- Separar consentimento de registro local do consentimento de compartilhamento com medico.
- Permitir revogacao de consentimento e bloqueio de compartilhamento.
- Informar finalidade: acompanhamento longitudinal e apoio a decisao clinica.

## Minimizacao

- Coletar apenas dados necessarios ao acompanhamento.
- Evitar campos livres obrigatorios.
- Reduzir acesso medico aos pacientes vinculados.

## Controle de acesso

- Autenticacao por JWT.
- Senhas armazenadas com hash bcrypt.
- Perfis separados: paciente e medico.
- Medico so acessa paciente vinculado.
- Acesso sensivel deve gerar log de auditoria.

## Seguranca

- Usar HTTPS obrigatorio em producao.
- Usar PostgreSQL gerenciado com backup criptografado.
- Usar `NEUROFLOW_FIELD_ENCRYPTION_KEY` para criptografia de campos sensiveis.
- Guardar segredos em cofre do provedor, nunca no repositorio.
- Rotacionar chaves de JWT e criptografia com plano de migracao.

## Retencao e exclusao

- Definir prazo de retencao antes do lancamento.
- Permitir exportacao dos dados do titular.
- Permitir exclusao/anominizacao quando legalmente aplicavel.
- Registrar solicitacoes de acesso, correcao e exclusao.

## Controles tecnicos ja previstos no backend

- Portabilidade: `GET /me/export` exporta usuario, check-ins, escalas, alertas, relatorios e auditoria.
- Auditoria: `GET /me/audit-logs` permite consultar eventos associados ao usuario.
- Retencao: `DELETE /me/clinical-data?days_older_than=365` remove dados clinicos antigos conforme prazo definido.
- Exclusao: `DELETE /me` remove conta, vinculos, tokens e dados clinicos do usuario no backend.
- Criptografia de campos sensiveis: diario, pensamentos, efeitos colaterais, mensagens de alerta e relatorios usam Fernet via `NEUROFLOW_FIELD_ENCRYPTION_KEY`.

Esses controles nao substituem revisao juridica. Eles sao base tecnica para implementar direitos do titular, retencao e auditoria.

## Incidentes

- Definir responsavel por resposta a incidente.
- Registrar impacto, usuarios afetados, dados expostos e mitigacao.
- Notificar titulares e autoridade competente quando aplicavel.

## Pendencias antes de producao

- Termo de uso.
- Politica de privacidade publica.
- DPA/contratos com provedores.
- Processo formal para direitos do titular.
- DPIA/RIPD para dados sensiveis.
