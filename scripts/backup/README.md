# Backups do Neuremia

Estado: rotina preparada; só considerar ativa após uma execução verde no GitHub Actions.

O workflow `Encrypted database backup` roda diariamente às 03:23 de São Paulo
(o GitHub pode atrasar execuções) e permite execução manual. Guarda um artefato
criptografado por 30 dias. Falhas podem ser notificadas pelas preferências de
notificação do GitHub Actions da conta proprietária.

## Configurar em Settings → Secrets and variables → Actions

- `BACKUP_DATABASE_URL`: conexão do Session pooler Supabase usada pela API.
- `NEUREMIA_FIELD_ENCRYPTION_KEY`: mesma chave Fernet já usada no Railway.
- `BACKUP_ENCRYPTION_KEY`: outra chave Fernet, exclusiva para os backups.

Gerar a chave exclusiva no Terminal:

```sh
Backend/.venv/bin/python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
```

Guardar uma cópia dessa chave em um gerenciador de senhas, separado do GitHub.
O GitHub não permite reler o valor de um secret. Nunca colocar chaves no Git.
Ao trocar a chave dos backups, preservar as antigas até expirarem todas as cópias
que dependem delas. A chave dos campos clínicos é incluída dentro do pacote criptografado.

## Primeira execução e verificação

Em Actions, escolher `Encrypted database backup` → Run workflow.
Confirmar que `Create encrypted backup` e `Verify restore in disposable database`
passaram e que existe o artefato. Uma cópia pode existir mesmo se a verificação
falhar: nesse caso não tratá-la como backup validado.

O teste restaura o arquivo em um PostgreSQL temporário isolado, verifica tabelas
essenciais e tenta descriptografar um nome de usuário se houver registros.
Não escreve no banco de origem. O teste local do script não substitui este teste real.

## Recuperação

Baixar e descompactar um artefato antes de seus 30 dias de validade. Em ambiente
seguro com PostgreSQL 17 client e Python cryptography, definir as variáveis
`BACKUP_ENCRYPTION_KEY` e `RESTORE_DATABASE_URL` (destino vazio) e executar:

```sh
python3 scripts/backup/backup.py verify /caminho/neuremia.enc
```

Esse comando efetivamente restaura no destino e se recusa a sobrescrever tabelas
existentes. Para voltar a servir a aplicação, configurar a API para o banco
restaurado e recuperar a chave `field_key` do pacote em ambiente seguro. Não
imprimir o conteúdo do pacote em logs ou enviar para o chat.

## Cobertura e limites

Inclui somente o schema `public` (tabelas do backend), com dados, índices e a
versão Alembic. Não inclui Supabase Storage, Auth, funções de outros schemas,
roles, senhas de roles, credenciais de push ou configurações do Railway.
Permissões de banco devem ser revisadas ao recuperar em um novo Supabase.
Uma execução diária permite perder até cerca de 24 horas de dados; atrasos ou
falhas aumentam essa janela. Retenção de 30 dias não é arquivo permanente.
O uso do GitHub Actions e do armazenamento consome a franquia da conta.
