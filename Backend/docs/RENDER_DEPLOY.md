# Publicar a API no Render

O ficheiro [`render.yaml`](../../render.yaml) cria a API FastAPI e liga-a a um PostgreSQL gerenciado.

## Configuração

1. No Render, escolha **New > Blueprint** e selecione este repositório.
2. Confirme os serviços definidos em `render.yaml`.
3. No serviço `neuremia-api`, defina `NEUREMIA_FIELD_ENCRYPTION_KEY` com uma chave gerada por:

   ```bash
   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
   ```

4. Depois do primeiro deploy, copie o hostname público do serviço (por exemplo, `neuremia-api.onrender.com`) e atualize:
   - `NEUREMIA_ALLOWED_HOSTS` para esse hostname;
   - `NEUREMIA_ALLOWED_ORIGINS` para os domínios web que farão chamadas, se existirem.
5. Confirme `GET https://<hostname>/health` e `GET https://<hostname>/ready`.

As chaves geradas pelo Render ficam como variáveis secretas. Não as coloque no Git nem no projeto iOS.

## Ligar o app iOS

Em `Neuremia/Config/Release.xcconfig`, substitua o placeholder de `INFOPLIST_KEY_NeuremiaAPIBaseURL` pela URL HTTPS pública do serviço. O valor deve terminar no host da API, sem `/v1`; o cliente acrescenta esse caminho automaticamente.

Depois, execute:

```bash
bash scripts/validate_release_config.sh
```
