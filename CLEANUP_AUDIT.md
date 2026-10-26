# Auditoria de limpeza segura — Neuremia

Data: 10/09/2026. Estado de referência: arquivos locais existentes no início da auditoria, incluindo alterações staged, unstaged e arquivos novos. Nenhum commit, push, reset ou alteração do índice foi realizado.

## Estrutura e arquitetura

- 31 arquivos Swift: 28 de aplicação (incluindo PatientEnhancementComponents.swift na raiz), um de testes unitários e dois de testes UI.
- Um projeto Neuremia.xcodeproj e seu workspace interno. Scheme compartilhado Neuremia; targets Neuremia, NeuremiaTests e NeuremiaUITests; configurações Debug e Release; deployment target iOS 26.4.
- Entrada: NeuremiaApp (@main), adaptador AppDelegate, ModelContainer SwiftData e ContentView. ContentView é repartida por extensões; possui estado, queries, navegação de paciente/médico, onboarding, consentimento, configurações, escalas e telas modais.
- SwiftUI, UIKit, SwiftData com schemas V1/V2/V3 e migrações, Combine, async/await, Charts, HealthKit, AVFoundation, BackgroundTasks, UserNotifications/APNs, Network, CryptoKit, Security/Keychain, Foundation e os.
- Sem targets de widgets/extensions, pacotes Swift, CocoaPods, frameworks locais, StoreKit, CloudKit, App Intents ou integração Firebase identificada. Menção textual a Firebase não é uma dependência.
- Configuração: dois xcconfig, Info.plist, dois entitlements, scheme e script de validação de Release. Sem storyboards, XIBs, fontes, strings/string catalogs ou fixtures JSON de aplicação identificados. Textos de UI ficam em Swift.
- Assets: um catálogo, AppIcon com três PNGs e AccentColor; três Contents.json. SF Symbols são carregados por systemName, inclusive nomes calculados, e não são arquivos removíveis do catálogo.
- Backend separado: FastAPI/SQLAlchemy, 60 arquivos Python entre aplicação, testes e 13 migrações, requirements.txt, Docker, documentação e configuração Alembic. Ambiente virtual e banco local preservados; não foram lidos dados clínicos nem segredos.
- Mocks MockURLProtocol/MockChallengeSender usados pelos testes; testes Swift Testing/XCTest e preview de ContentView preservados.

## Classificação e código morto removido

Todos os itens abaixo foram considerados SAFE_TO_DELETE pela análise de referências antes da remoção. Busca em todo o código e configurações, incluindo testes, navegação, previews e mecanismos de carregamento dinâmico. São structs privadas SwiftUI sem registro externo ou efeitos de inicialização globais.

| Elemento em ContentViewComponents.swift | Evidência |
|---|---|
| DailyCoachPredictionPill | Somente declaração; duplica exatamente a apresentação de RetentionMetricPill, que foi preservada. |
| DailyRetentionNarrativeRow | Somente declaração; nenhum consumidor ou preview. |
| DailyScoreReliabilityRow | Somente declaração; nenhum consumidor ou preview. |
| ScoreSignalPill | Chamado exclusivamente dentro de DailyScoreReliabilityRow, também removida. |
| DailyCoachActionRow | Somente declaração; nenhum consumidor ou preview. |

Foram removidas também as propriedades e funções internas desses cinco componentes. Nenhum ViewModel, modelo persistente, serviço ou arquivo Swift inteiro foi removido.

Imports SAFE_TO_DELETE: SwiftUI em HapticManager.swift (usa UIKit/Dispatch, sem tipos SwiftUI); Charts em ClinicalScalesView.swift (compõe outros componentes e não usa APIs Charts). Build confirmou resolução dos símbolos após ambas as remoções.

## Removed files

Somente caches Python .pyc regeneráveis, cada um com arquivo .py correspondente ainda presente. Não são recursos do Xcode e já são ignorados por __pycache__/ e *.py[cod]. Nenhuma alteração de .gitignore foi necessária. Relação completa abaixo.

- `Backend/app/__pycache__/security.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/security.py`.
- `Backend/app/__pycache__/dependencies.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/dependencies.py`.
- `Backend/app/__pycache__/schemas.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/schemas.py`.
- `Backend/app/__pycache__/main.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/main.py`.
- `Backend/app/__pycache__/interventions.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/interventions.py`.
- `Backend/app/__pycache__/notifications.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/notifications.py`.
- `Backend/app/__pycache__/models.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/models.py`.
- `Backend/app/__pycache__/baselines.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/baselines.py`.
- `Backend/app/__pycache__/__init__.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/__init__.py`.
- `Backend/app/__pycache__/rate_limit.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/rate_limit.py`.
- `Backend/app/__pycache__/episode_pipeline.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/episode_pipeline.py`.
- `Backend/app/__pycache__/services.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/services.py`.
- `Backend/app/__pycache__/database.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/database.py`.
- `Backend/app/routers/__pycache__/clinician.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/clinician.py`.
- `Backend/app/routers/__pycache__/checkins.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/checkins.py`.
- `Backend/app/routers/__pycache__/patients.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/patients.py`.
- `Backend/app/routers/__pycache__/caregivers.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/caregivers.py`.
- `Backend/app/routers/__pycache__/auth.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/auth.py`.
- `Backend/app/routers/__pycache__/admin.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/admin.py`.
- `Backend/app/routers/__pycache__/devices.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/devices.py`.
- `Backend/app/routers/__pycache__/totp.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/totp.py`.
- `Backend/app/routers/__pycache__/__init__.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/__init__.py`.
- `Backend/app/routers/__pycache__/me.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/app/routers/me.py`.
- `Backend/tests/__pycache__/test_e2e_critical_flows.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_e2e_critical_flows.py`.
- `Backend/tests/__pycache__/test_security_contracts.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_security_contracts.py`.
- `Backend/tests/__pycache__/test_export_pagination.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_export_pagination.py`.
- `Backend/tests/__pycache__/test_sprint15.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_sprint15.py`.
- `Backend/tests/__pycache__/test_episode_pipeline.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_episode_pipeline.py`.
- `Backend/tests/__pycache__/test_sprint13.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_sprint13.py`.
- `Backend/tests/__pycache__/test_auth.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_auth.py`.
- `Backend/tests/__pycache__/test_sprint10.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_sprint10.py`.
- `Backend/tests/__pycache__/test_lgpd_endpoints.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_lgpd_endpoints.py`.
- `Backend/tests/__pycache__/test_soft_deletes.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_soft_deletes.py`.
- `Backend/tests/__pycache__/conftest.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/conftest.py`.
- `Backend/tests/__pycache__/test_caregivers.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_caregivers.py`.
- `Backend/tests/__pycache__/test_invites.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_invites.py`.
- `Backend/tests/__pycache__/test_admin_ops_status.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_admin_ops_status.py`.
- `Backend/tests/__pycache__/test_personal_baselines.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_personal_baselines.py`.
- `Backend/tests/__pycache__/__init__.cpython-314.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/__init__.py`.
- `Backend/tests/__pycache__/test_refresh_tokens.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_refresh_tokens.py`.
- `Backend/tests/__pycache__/test_sprint14.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_sprint14.py`.
- `Backend/tests/__pycache__/test_medium_priority.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_medium_priority.py`.
- `Backend/tests/__pycache__/test_authorization.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_authorization.py`.
- `Backend/tests/__pycache__/test_clinical_validation.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_clinical_validation.py`.
- `Backend/tests/__pycache__/test_production_readiness.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_production_readiness.py`.
- `Backend/tests/__pycache__/test_notifications_phi.cpython-314-pytest-8.4.2.pyc` — SAFE_TO_DELETE, cache de `Backend/tests/test_notifications_phi.py`.

## Assets removed

Nenhum. AppIcon e AccentColor: KEEP, referenciados por ASSETCATALOG_COMPILER_APPICON_NAME e ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME. Os três PNGs são idênticos por SHA-256, mas estão referenciados em Contents.json para aparências diferentes; preservados. Não há imagens soltas de aplicação candidatas à remoção.

## Dependencies removed

Nenhuma. iOS: zero dependências externas antes/depois; frameworks Apple necessários permanecem disponíveis.

| Backend requirements.txt | Classificação | Evidência |
|---|---|---|
| fastapi, sqlalchemy, pydantic[email] | USED | Rotas, modelos, schemas e EmailStr. |
| uvicorn[standard], alembic | USED | Inicialização Docker e migrações. |
| psycopg[binary] | POSSIBLY USED | Driver PostgreSQL de implantação; banco configurado por DATABASE_URL. |
| pyjwt, cryptography, bcrypt, pyotp | USED | Tokens, criptografia e autenticação em security.py. |
| slowapi | USED | Rate limiting. |
| pytest, httpx | USED | Suíte backend e TestClient. |
| python-multipart | POSSIBLY USED | Nenhum formulário/upload direto localizado; mantido por conservadorismo no ambiente backend, fora da compilação iOS. |

## Kept for safety

- REVIEW: EpisodeRiskCard, EpisodePredictionCard, AppointmentEventCard e PersonalRetentionModelCard não têm consumidores Swift diretos localizados. Fazem parte de alterações locais funcionais ainda não commitadas; preservados para não descartar possíveis telas em integração. Helpers exclusivos também preservados.
- REVIEW: outros imports possivelmente redundantes (Charts em PatientEvolutionView/ClinicianDashboard/ContentView+ClinicianPatients e SwiftData em arquivos de componentes). Não removidos sem validação específica de cada grupo.
- KEEP: @UIApplicationDelegateAdaptor appDelegate, mesmo sem leitura explícita; ativa callbacks do ciclo de vida.
- KEEP: schemas/migrações SwiftData e Alembic, enums Codable, chaves persistidas/legadas, callbacks HealthKit/APNs, configurações legais, autenticação/Keychain, backup e notificações. Uso indireto impede exclusões por simples contagem textual.
- KEEP: PatientDiaryView e PatientDiaryProgressiveView contêm extensões diferentes usadas pela aplicação; não são cópias por nome.
- KEEP: PatientEnhancementComponents.swift está explicitamente em Sources; os diretórios Neuremia/Tests/UITests usam grupos sincronizados do Xcode. Não foi necessário editar project.pbxproj.
- KEEP: __init__.py vazios duplicados são marcadores de pacotes, não resíduos.
- REVIEW: MANUAL_CLEANUP.md contém orientações antigas sobre NeuroFlow; preservado como histórico. Nenhuma instrução de reescrita do Git nele foi executada.
- KEEP: documentos HTML do piloto, privacidade e auditorias, ambiente virtual e banco local. Não são descartáveis por estarem fora do bundle iOS.
- KEEP: .git/.DS_Store, por estar dentro dos metadados Git fora do escopo de edição.

## Warnings

- Antes e depois: “Metadata extraction skipped. No AppIntents.framework dependency found.” Emitido pelo Xcode; não foi adicionada dependência artificial para silenciá-lo.
- Não foram encontrados warnings de código Swift não utilizado nos builds bem-sucedidos.
- Validação de Release existente falha por URL api.your-domain.com e falta de associação do target Release a NeuremiaRelease.entitlements. Problemas anteriores à limpeza; configuração de assinatura preservada. Build de simulador não valida distribuição App Store.

## Build validation

O xcode-select global aponta para CommandLineTools. Foi usado DEVELOPER_DIR por comando, sem alterar a configuração global. A primeira tentativa em sandbox falhou no catálogo por falta de acesso ao CoreSimulator; repetição autorizada com acesso ao serviço passou.

Comando de referência e após alterações (ambos BUILD SUCCEEDED):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Neuremia.xcodeproj -scheme Neuremia -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/neuremia-cleanup-build CODE_SIGNING_ALLOWED=NO build
```

Logs: /tmp/neuremia-baseline-full.log e /tmp/neuremia-cleanup-build.log.

Testes existentes:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Neuremia.xcodeproj -scheme Neuremia -configuration Debug \
  -destination 'platform=iOS Simulator,id=B30D988B-094C-4516-B6AB-B86B51DC1252' \
  -derivedDataPath /tmp/neuremia-cleanup-build \
  -resultBundlePath /tmp/neuremia-cleanup-tests.xcresult CODE_SIGNING_ALLOWED=NO test
```

Resultado da primeira tentativa: 73 casos reportados, 44 aprovados e 29 falhos no resumo global do xcresult. Destes, 26 são marcados como “Test crashed with signal trap”, um é uma expectativa divergente em longitudinalSummaryDetectsWorseningMoodAndAdherence (high obtido, moderate esperado), e dois registros pertencem ao cancelamento da UI. A execução foi interrompida após falta de progresso da UI; esses totais não representam uma suíte completa validada. Comparação unitária concluída, em cópia isolada dos fontes anteriores e depois no repositório limpo, com as mesmas opções: **63 aprovados, 9 falhos, 72 casos reportados em ambos**. O conjunto de identificadores falhos é idêntico; nenhuma nova falha detectada. Os totais incluem um registro de issues sem teste associado.

Opções adicionais da comparação: `-only-testing:NeuremiaTests -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 60`. A referência usou `/tmp/neuremia-cleanup-baseline-source`, DerivedData `/tmp/neuremia-baseline-test-build` e result bundle `/tmp/neuremia-baseline-unit.xcresult`. A versão limpa usou o repositório original, DerivedData `/tmp/neuremia-cleanup-build` e `/tmp/neuremia-cleanup-unit.xcresult`. Logs em `/tmp/neuremia-baseline-unit.log` e `/tmp/neuremia-cleanup-unit.log`.

Falhas preexistentes reproduzidas:

- `longitudinalSummaryDetectsWorseningMoodAndAdherence`: espera moderate e recebe high.
- `fourteenDayStreakAwardsConfiguredBonusXP`: espera 250 XP e recebe 350.
- `dailyCoachScoreExplainsWeeklyTrendAndPreCrisisPattern`: expectativas de driver e confiabilidade divergentes.
- `backendLevelMapsKnownTiersAndFailsSafeOnUnknown`: `fatalError` em BackupView.swift para critical-emergency (signal trap).
- `coordinatorKeepsSessionOnNetworkFailure` e `refreshCoordinatorIsSingleFlightUnderConcurrentRequests`: expectativas de tokens/contagem de refresh não satisfeitas.
- `linkedCliniciansDecodesAndCanBeRevoked` e `authenticatedRequestRetriesOnceAfter401`: erro 404.
- Issues sem teste associado: caminhos esperados pelos mocks diferem dos caminhos /v1 enviados; divergência de query também registrada.

Não foram alterados testes ou funcionalidades para contornar essas falhas. A comparação unitária não substitui validação manual dos fluxos, sensores, APNs e distribuição. A UI permanece sem validação completa.

O coletor de diagnósticos do simulador também informou que não encontrou simctl em uma etapa interna, apesar do DEVELOPER_DIR fornecido ao xcodebuild; resultados dos testes foram produzidos.

Build Release de simulador: BUILD SUCCEEDED, com o mesmo comando de build acima trocando -configuration Debug por -configuration Release. Log: /tmp/neuremia-cleanup-release.log. Plists, entitlements e project.pbxproj passaram em plutil -lint.

`git diff --check`: passou. `bash scripts/validate_release_config.sh`: falhou pelos dois problemas de Release descritos acima. Backend não alterado funcionalmente; suíte backend não executada.

## Optimization summary

- Arquivos de fonte/configuração/documentação visíveis por rg: 127 antes → 127 depois da limpeza; este relatório adiciona um arquivo de documentação.
- Arquivos locais excluindo .git, incluindo ambiente virtual/caches: 3089 → 3043 antes de adicionar este relatório; 46 caches removidos.
- Swift: 31 → 31 arquivos; cinco structs privadas e dois imports removidos, 172 linhas e 5,842 bytes de fonte a menos.
- Assets: 2 conjuntos → 2; PNGs: 3 → 3; dependências externas iOS: 0 → 0; requisitos backend: 14 → 14.
- Caches removidos: 828,961 bytes. Redução bruta local (fonte + caches): 834,803 bytes, aproximadamente 815.2 KiB. Não inclui o novo relatório nem artefatos de validação em /tmp.
- Não foi medida redução do binário/IPA. Remoção de código não alcançável pode não alterar o binário otimizado. Os caches podem ser recriados pelo Python.
