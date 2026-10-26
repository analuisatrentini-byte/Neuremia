# App Store Release Audit - Neuremia

Data da auditoria: 2026-09-10  
Escopo: app iOS Neuremia, target principal, testes, Info.plist, entitlements, xcconfigs, assets, permissões, privacidade, segurança, Release/Archive e riscos de App Review.

Referências atuais consultadas:
- Apple Upcoming Requirements: uploads para App Store Connect exigem Xcode 26+ e SDK iOS/iPadOS 26+ desde 2026-04-28; SDK 27 será exigido a partir de 2027-04.
- App Review Guidelines: 1.4.1, 1.6, 2.1, 2.3.1, 4.8, 5.1.1, 5.1.2 e 5.1.3.
- Apple User Privacy and Data Use: declaração de privacidade inclui código próprio e terceiros; tracking exige ATT; fingerprinting é proibido.
- Apple Privacy Manifest / Required Reason APIs: `UserDefaults` exige `NSPrivacyAccessedAPICategoryUserDefaults` com razão permitida, tipicamente `CA92.1` quando usado apenas pelo próprio app.

Legenda:
- VERIFIED: confirmado no código/configuração ou por comando executado.
- INFERRED: inferido por leitura estática do código, sem execução completa do fluxo.
- NOT TESTED: não executado no ambiente atual.
- REQUIRES HUMAN REVIEW: depende de decisão clínica, legal, Apple Developer, App Store Connect ou backend de produção.

## 1. Executive Summary

O Neuremia ainda não está pronto para submissão na App Store. Há problemas de configuração de Release, privacidade, armazenamento de dados sensíveis e completude de backend que precisam ser resolvidos antes de Archive/Upload/App Review.

Pontos principais:
- VERIFIED: o build pelo Xcode MCP passou sem warnings registrados, usando SDK iPhoneOS 26.5.
- VERIFIED: `xcodebuild` Debug/Release/Archive falhou neste ambiente por erro de CoreSimulator/actool, não por erro Swift confirmado.
- VERIFIED: o target Release não aponta para `Neuremia/NeuremiaRelease.entitlements`, embora o arquivo exista.
- VERIFIED: não existe `PrivacyInfo.xcprivacy`, mas o app usa `@AppStorage`/`UserDefaults`, uma Required Reason API.
- VERIFIED: `Release.xcconfig` ainda usa endpoint placeholder `https://api.your-domain.com`, e o código transforma isso em domínio `.invalid`.
- VERIFIED/INFERRED: há dados sensíveis de saúde/saúde mental em SwiftData e em `UserDefaults`; logout limpa tokens e alguns caches, mas não remove todos os registros clínicos locais.
- REQUIRES HUMAN/CLINICAL REVIEW: Neuremia Score, predições de risco, interpretações de escalas, sinais biométricos e textos clínicos podem ser interpretados como diagnóstico, triagem ou orientação médica.

## 2. Blockers

| ID | Severidade | Evidência | Problema | Impacto | Correção recomendada |
|---|---|---|---|---|---|
| B-001 | BLOCKER | VERIFIED | `PrivacyInfo.xcprivacy` ausente, apesar do uso de `UserDefaults`/`@AppStorage`. | App Store Connect pode recusar processamento por Required Reason API não declarada. | Adicionar `Neuremia/Neuremia/PrivacyInfo.xcprivacy` com `NSPrivacyAccessedAPICategoryUserDefaults` e razão `CA92.1`; validar no Archive. |
| B-002 | BLOCKER | VERIFIED | Release não configura `CODE_SIGN_ENTITLEMENTS`, enquanto Debug usa `NeuremiaDebug.entitlements` e existe `NeuremiaRelease.entitlements`. | Archive/Upload pode sair sem HealthKit/APNs ou falhar por capability/provisioning inconsistente. | No Xcode, definir Code Signing Entitlements do target Neuremia Release para `Neuremia/NeuremiaRelease.entitlements`. |
| B-003 | BLOCKER | VERIFIED | `Release.xcconfig` contém `NeuremiaAPIBaseURL = https://api.your-domain.com`; o código considera placeholder e usa `.invalid`. | Login, registro, exportação remota, exclusão de conta e funções clínicas remotas não funcionarão no App Review. Guideline 2.1 exige backend ativo. | Configurar domínio HTTPS real de produção, backend ativo, conta demo ou demo mode aprovado, e validar flows em dispositivo físico Release. |

## 3. Critical Issues

| ID | Severidade | Evidência | Problema | Impacto | Correção recomendada |
|---|---|---|---|---|---|
| C-001 | CRITICAL | VERIFIED/INFERRED | Dados de saúde agregados ficam em `UserDefaults` via `@AppStorage` (`latestSteps`, sono, HR, HRV, energia, baseline, reconciliação HealthKit). | Dados sensíveis ficam em armazenamento não criptografado pelo app e podem ser incluídos em backup do dispositivo. Risco de 1.6 e 5.1.1. | Migrar dados sensíveis para store protegida/encriptada ou SwiftData com file protection; reduzir `UserDefaults` a preferências não sensíveis. |
| C-002 | CRITICAL | VERIFIED/INFERRED | `logout()` limpa tokens, APNs, drafts e caches, mas não remove todos os objetos SwiftData clínicos locais (`DailyCheckIn`, avaliações, relatórios, alertas). | Outro usuário no mesmo dispositivo pode herdar histórico sensível após logout. | Separar logout de limpeza local, mas oferecer e executar limpeza local completa quando trocar conta ou excluir conta; escopar dados por usuário autenticado. |
| C-003 | CRITICAL | VERIFIED | `NeuremiaApp.swift` pode apagar/recriar o store SwiftData quando detecta fingerprint de modelo diferente. | Atualização de versão pode causar perda de registros de saúde/diário. | Implementar migrações SwiftData explícitas ou export/backup/consentimento antes de destruição de store; tratar como REQUIRES HUMAN REVIEW. |

## 4. High Priority Issues

| ID | Severidade | Evidência | Problema | Impacto | Correção recomendada |
|---|---|---|---|---|---|
| H-001 | HIGH | VERIFIED | `DataResidencyPolicy.localOnlyMode = true`, mas documentos/UI descrevem backend, profissionais, exportação, auditoria e exclusão remota. | Inconsistência entre funcionalidade real, política de privacidade, screenshots/metadados e App Review. | Decidir se Release será local-only ou conectado; alinhar UI, política, App Privacy e backend. REQUIRES HUMAN REVIEW. |
| H-002 | HIGH | VERIFIED | O app permite criação/login de conta no código, mas backend Release está inválido. | Guideline 2.1: reviewer não consegue testar recursos baseados em conta; exclusão de conta pode ser considerada indisponível. | Backend de produção funcional ou remover/ocultar conta no build App Store se o produto for 100% local. |
| H-003 | HIGH | VERIFIED/INFERRED | Notificações locais têm conteúdo como "Hora da medicação". | Pode revelar dado de saúde na tela bloqueada. | Usar texto neutro ou permitir opção de privacidade para conteúdo de notificações. |
| H-004 | HIGH | VERIFIED | Política/legal menciona menores com consentimento do responsável, mas não foi encontrado fluxo de idade/guardião. | Risco legal/App Review para saúde mental e privacidade infantil. | Definir elegibilidade, faixa etária, consentimento parental e metadados de idade. REQUIRES HUMAN REVIEW. |
| H-005 | HIGH | VERIFIED/INFERRED | HealthKit background delivery entitlement existe, mas a auditoria não confirmou capability/provisioning/App ID. | Upload/Archive pode falhar se App ID não tiver HealthKit e Push habilitados. | Conferir Apple Developer: App ID `ALTB.Neuremia`, HealthKit, background delivery e Push. REQUIRES CONFIGURATION. |

## 5. Info.plist Audit

| Chave | Status | Evidência | Avaliação |
|---|---|---|---|
| `CFBundleDisplayName` | REVIEW REQUIRED | VERIFIED | Usa `$(INFOPLIST_KEY_CFBundleDisplayName)` e xcconfig define "Neuremia". O pedido menciona "NeuroFlow"; alinhar nome de produto, marca, App Store metadata e textos. |
| `CFBundleIdentifier` | REVIEW REQUIRED | VERIFIED | `ALTB.Neuremia`. Deve existir exatamente no Apple Developer/App Store Connect. |
| `CFBundleShortVersionString` | OK | VERIFIED | `1.0`. |
| `CFBundleVersion` | OK | VERIFIED | `1`. |
| `NeuremiaAPIBaseURL` | BLOCKER | VERIFIED | Debug local HTTP; Release placeholder `.your-domain.com`. Release não está pronto. |
| `NeuremiaPinnedCertHashes` | REVIEW REQUIRED | VERIFIED | Vazio. Código aceita trust padrão se vazio; política fala em pinning opcional. Se pinning for promessa de produção, configurar hashes reais. |
| `NeuremiaPolicyVersion` | OK/REVIEW | VERIFIED | `1.1`, igual aos documentos legais lidos. Conteúdo legal requer revisão humana. |
| `BGTaskSchedulerPermittedIdentifiers` | OK | VERIFIED | Contém `ALTB.Neuremia.backup-refresh`; código registra/schedule com este ID. |
| `UIBackgroundModes` | OK/REVIEW | VERIFIED | `fetch`; coerente com BGAppRefresh. Confirmar se backup/sync em background é realmente necessário no produto final. |
| `NSCameraUsageDescription` | OK | VERIFIED | Texto específico e condicionado à medição iniciada pelo usuário. |
| `NSMicrophoneUsageDescription` | OK | VERIFIED | Texto específico e condicionado à análise iniciada pelo usuário. |
| `NSHealthShareUsageDescription` | OK/REVIEW | VERIFIED | Texto explica leitura de sono, passos, HR, HRV e energia. HealthKit é usado. |
| `NSUserTrackingUsageDescription` | OK ausente | VERIFIED | ATT não encontrado; não declarar se não há tracking. |
| Location/Contacts/Calendar/Bluetooth/Photos/Speech/Face ID | OK ausente | VERIFIED | APIs correspondentes não encontradas na busca estática. |
| ATS exceptions | OK ausente | VERIFIED | Não há `NSAppTransportSecurity`; bom. |
| `UILaunchScreen` | OK | VERIFIED | Usa launch screen gerado por plist. |

## 6. Entitlements Audit

| Arquivo/Capability | Status | Evidência | Avaliação |
|---|---|---|---|
| `NeuremiaDebug.entitlements` | OK | VERIFIED | `aps-environment=development`, HealthKit e HealthKit background delivery. |
| `NeuremiaRelease.entitlements` | OK arquivo, BLOCKER config | VERIFIED | `aps-environment=production`, HealthKit e HealthKit background delivery. Arquivo existe, mas Release target não o referencia. |
| Push Notifications | REVIEW REQUIRED | VERIFIED/INFERRED | Código registra APNs apenas em ação/configuração, mas App ID/provisioning precisam ter Push production. |
| HealthKit | REVIEW REQUIRED | VERIFIED | Código solicita leitura HealthKit; entitlement necessário. Confirmar capability no App ID. |
| Associated Domains, Sign in with Apple, Keychain Sharing, App Groups, iCloud, Apple Pay | OK ausente | VERIFIED | Não encontrados nos entitlements. Não habilitar sem uso real. |

## 7. Permissions Audit

| API protegida | Uso encontrado | Info.plist | Momento da solicitação | Resultado |
|---|---|---|---|---|
| Camera | `AVCaptureDevice.requestAccess(for: .video)` em biometria PPG | Presente | Após fluxo de consentimento/ação de medição | OK, texto adequado. |
| Microphone | `AVAudioApplication.requestRecordPermission` / `AVAudioSession.requestRecordPermission` | Presente | Após fluxo de consentimento/ação de análise | OK, texto adequado. |
| HealthKit | Leitura de sono, passos, HR, resting HR, HRV, energia | Presente | Fluxo HealthKit | OK funcional, mas armazenamento local precisa revisão. |
| Notifications | `UNUserNotificationCenter.requestAuthorization` | Não exige usage key | Ao configurar lembretes/APNs | OK, mas conteúdo de medicação é sensível. |
| Tracking/ATT | Não encontrado | Ausente | N/A | OK. |
| Photos/Location/Contacts/Calendar/Bluetooth/Speech/Face ID | Não encontrado | Ausente | N/A | OK. |

## 8. Privacy Manifest Audit

Privacy Manifest atual: ausente.

Required Reason APIs encontradas:

| API/categoria | Evidência | Razão provável | Status |
|---|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | Uso extensivo de `@AppStorage`, `UserDefaults`, `EncryptedDefaultsStore`, `HealthKitPipelineStore` | `CA92.1`, se os defaults são usados apenas pelo app | BLOCKER até adicionar manifest. |

Não foram confirmadas chamadas diretas a categorias Required Reason de timestamp de arquivo, espaço em disco, boot time ou active keyboards. Ainda assim, validar com `xcodebuild archive` e App Store Connect é obrigatório.

Manifest recomendado mínimo:

```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
      <string>CA92.1</string>
    </array>
  </dict>
</array>
<key>NSPrivacyTracking</key>
<false/>
```

Não foi aplicado automaticamente porque o Xcode está aberto e a alteração de inclusão no target pode mexer no projeto. Criar pelo Xcode e confirmar que entra no target principal.

## 9. App Privacy / Data Collection Map

Esta tabela é base técnica para App Store Connect. Deve ser revisada por jurídico/produto, especialmente porque o backend Release está desabilitado por placeholder.

| Tipo de dado | É coletado? | Vinculado à identidade? | Tracking? | Finalidade | Onde é armazenado | Enviado a terceiros? | Código/SDK |
|---|---:|---:|---:|---|---|---:|---|
| Nome, e-mail, user ID | Sim se conta for usada | Sim | Não encontrado | Conta, autenticação, vínculo paciente/profissional | Keychain local; backend se ativo | Não encontrado | `BackendAuthClient`, `SettingsView` |
| Senha | Transmitida no login/registro | Sim | Não | Autenticação | Não armazenada no app; backend não auditado aqui | Não encontrado | `BackendAuthClient` |
| Tokens auth/refresh | Sim | Sim | Não | Sessão segura | Keychain | Não | `BackendAuthClient` |
| Token APNs | Sim se push ativado | Sim se enviado ao backend | Não | Notificações remotas | Keychain; backend se ativo | Apple APNs | `BackupView`, `BackendAuthClient` |
| Check-ins de humor/ansiedade/energia/sono/medicação/ideação | Sim | Localmente; sim se conta/sync | Não | Diário, acompanhamento, relatórios | SwiftData; backup; backend se ativo | Não encontrado | `ClinicalModels`, `BackupView`, `ContentView` |
| Texto livre e safety plan | Sim se usuário preencher | Localmente; sim se conta/sync | Não | Diário, alertas de segurança, relatório | Drafts criptografados; SwiftData/backup; backend se ativo | Não encontrado | `DraftStore`, `BackupView`, `ClinicalModels` |
| Escalas PHQ/GAD/YMRS/ASRM e interpretações | Sim | Localmente; sim se conta/sync | Não | Acompanhamento clínico/educativo | SwiftData; backup; backend se ativo | Não encontrado | `ClinicalAnalysis`, `ClinicalScalesView` |
| HealthKit: sono, passos, HR, HRV, energia | Sim após permissão | Localmente; sim se sync/conta | Não | Complementar registros de bem-estar | `UserDefaults`/`@AppStorage`, pipeline local; possivelmente relatórios | Apple Health origem dos dados; backend se ativo | `HealthKitPipeline`, `ContentView` |
| Métricas biométricas derivadas de câmera/microfone | Sim se usuário iniciar | Localmente | Não | Sinais corporais/voz para bem-estar | Estado local, baselines/relatórios conforme fluxo | Não encontrado por padrão | `BiometricManagers`, `PatientDiaryView` |
| Dados de digitação/comportamento local | Sim/inferido | Localmente | Não | Sinais heurísticos de estado | Modelos locais/SwiftData conforme fluxo | Não encontrado | `ClinicalModels`, `ContentView` |
| Logs/auditoria remota | Sim se backend ativo | Sim | Não | Segurança, rastreabilidade, exportação | Backend; app busca exibição | Não encontrado | `BackupView`, `BackendAuthClient` |
| Analytics/publicidade/attribution/session replay | Não encontrado | N/A | Não encontrado | N/A | N/A | N/A | Nenhum SDK encontrado |
| Crash reports de terceiros | Não encontrado | N/A | Não encontrado | N/A | N/A | N/A | Nenhum SDK encontrado |

## 10. Security Audit

| Área | Status | Evidência | Avaliação |
|---|---|---|---|
| API keys/secrets no app iOS | OK | VERIFIED | Não foram encontrados segredos hardcoded relevantes no app iOS; tokens de teste existem em testes/backend. |
| `.env` | OK/REVIEW | VERIFIED | `Backend/.env.example` tem placeholders. Backend não parece estar no bundle iOS. |
| Armazenamento de tokens | OK/REVIEW | VERIFIED | Tokens ficam no Keychain. `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` é forte, mas pode falhar em dispositivos sem senha; o código ignora parte dos retornos booleanos. |
| Dados de saúde em preferências | CRITICAL | VERIFIED | `@AppStorage`/`UserDefaults` guarda métricas sensíveis. |
| Backups locais | OK | VERIFIED | Backup usa proteção `.completeFileProtection`, exclusão de iCloud backup e criptografia de campos sensíveis. |
| Logs | REVIEW REQUIRED | VERIFIED/INFERRED | Não foi encontrado logging amplo de PHI, mas mensagens de erro exibem `localizedDescription`; revisar backend e analytics. |
| Networking | HIGH | VERIFIED | Release aponta para placeholder; código aceita URL HTTP se configurada. Sem ATS exception, HTTP falharia, mas Release deveria rejeitar HTTP explicitamente. |
| Certificate pinning | REVIEW REQUIRED | VERIFIED | Pinning opcional via hashes; vazio em Release. Decidir se é requisito de segurança/documentação. |

## 11. Third-Party SDK Audit

| Dependência | Versão | Finalidade | Privacy Manifest | Coleta de dados | Risco App Store |
|---|---|---|---|---|---|
| SwiftUI, SwiftData, HealthKit, AVFoundation, UserNotifications, BackgroundTasks, CryptoKit, Security | SDK iOS 26.5 local | Frameworks Apple | App deve declarar Required Reason APIs próprias | Conforme uso do app | HealthKit/privacidade exigem revisão. |
| SDKs externos iOS | Nenhum encontrado | N/A | N/A | N/A | OK, sem SDK de ads/analytics/crash/attribution encontrado. |
| Backend Python | Fora do bundle iOS | API própria | N/A para bundle iOS | Depende do backend | Precisa auditoria separada para produção, LGPD, retenção, segurança e logs. |

Não há Swift Packages, frameworks embedados ou bibliotecas externas iOS identificadas no `project.pbxproj`.

## 12. Release Build Audit

| Item | Status | Evidência |
|---|---|---|
| SDK atual | PASS | `xcodebuild` usou `/iPhoneOS26.5.sdk`, atendendo requisito atual de Xcode/SDK 26+. |
| Deployment Target | REVIEW REQUIRED | `IPHONEOS_DEPLOYMENT_TARGET = 26.4`; tecnicamente atual, mas limita usuários a iOS 26.4+. Confirmar estratégia de mercado. |
| Debug build via Xcode MCP | PASS | `BuildProject` retornou sucesso e `GetBuildLog` sem warnings. Configuração exata do scheme não foi confirmada como Debug pelo comando. |
| Debug explícito via `xcodebuild` | FAIL/ENV | Falhou em `CompileAssetCatalogVariant` por CoreSimulator/actool: `No available simulator runtimes for platform iphonesimulator`. |
| Release explícito via `xcodebuild` | FAIL/ENV | Mesmo erro ambiental de CoreSimulator/actool. |
| Archive explícito | FAIL/ENV | Mesmo erro ambiental de CoreSimulator/actool antes de concluir Archive. |
| Release entitlements | FAIL | Release target não aponta para `NeuremiaRelease.entitlements`. |
| Release backend | FAIL | Endpoint placeholder. |
| `#if DEBUG` | OK parcial | Menus/diagnósticos debug relevantes estão atrás de `#if DEBUG`; revisão estática não achou debug menu óbvio em Release. |
| Placeholders visíveis | REVIEW REQUIRED | Placeholder de backend em Release; textos legais/UI podem prometer recursos não funcionais. |

## 13. Signing & Provisioning

| Item | Status | Evidência | Ação |
|---|---|---|---|
| Team | REVIEW REQUIRED | `DEVELOPMENT_TEAM = X4LVNLD477` | Confirmar no Apple Developer. |
| Bundle ID | REVIEW REQUIRED | `ALTB.Neuremia` | Deve existir no App Store Connect e App ID. |
| Automatic signing | OK/REVIEW | `CODE_SIGN_STYLE = Automatic` | OK se conta Xcode tem permissões e capabilities corretas. |
| Provisioning Release | REQUIRES CONFIGURATION | Não validado | Precisa perfil com HealthKit, HealthKit background delivery e Push production. |
| Archive signing | NOT TESTED | Archive foi executado com `CODE_SIGNING_ALLOWED=NO` por auditoria local | Executar Archive real assinado no Xcode. |

## 14. App Review Risks

| Guideline | Risco | Severidade | Evidência |
|---|---|---|---|
| 2.1 App Completeness | Backend Release placeholder e conta/export/delete remotos não testáveis. | BLOCKER | VERIFIED |
| 2.3.1 Accurate Metadata | UI/política prometem backend/profissionais/conta enquanto Release está local-only/placeholder. | HIGH | VERIFIED |
| 5.1.1 Privacy | Dados sensíveis em `UserDefaults`; exclusão/revogação/limpeza local incompleta. | CRITICAL | VERIFIED/INFERRED |
| 5.1.1 Account deletion | App tem criação/login de conta no código; exclusão depende de backend funcional e autenticação. | HIGH/BLOCKER | VERIFIED |
| 1.6 Data Security | Proteção de dados locais sensíveis precisa reforço. | CRITICAL | VERIFIED |
| 1.4.1 Medical Apps | Predições, escalas, biometria e risco suicida podem ser interpretados como apoio clínico. | HIGH | VERIFIED/INFERRED |
| 5.1.3 Health Data | Uso de HealthKit e dados de saúde mental exige limitação de finalidade e política precisa. | HIGH | VERIFIED |
| 4.8 Sign in with Apple | Não aplicável atualmente: login social de terceiros não encontrado. | OK | VERIFIED |
| ATT/5.1.2 | Não aplicável atualmente: tracking/ads/analytics não encontrados. | OK | VERIFIED |

## 15. Health / Mental Health Review Risks

O app contém disclaimers importantes de bem-estar e não substituição de avaliação clínica, mas ainda usa linguagem e recursos que exigem revisão clínica.

| Área | Classificação | Risco | Ação |
|---|---|---|---|
| Neuremia Score | REQUIRES HUMAN/CLINICAL REVIEW | Pode ser percebido como score clínico proprietário, triagem ou predição. | Documentar metodologia, validação, limites e linguagem de incerteza. |
| PHQ/GAD/YMRS/ASRM | REQUIRES HUMAN/CLINICAL REVIEW | Escalas e interpretações precisam licença, uso correto, pontuação validada e contexto. | Revisão clínica/legal das escalas oficiais, traduções e permissões. |
| Predição 7/14 dias e "risco suicida" | REQUIRES HUMAN/CLINICAL REVIEW | Alto risco App Review/segurança se parecer diagnóstico, previsão médica ou manejo de crise. | Ajustar linguagem para acompanhamento educativo; ter fluxos de emergência claros e validados. |
| Biometria câmera/microfone | REQUIRES HUMAN/CLINICAL REVIEW | Estimativas de sinais corporais/voz podem ser vistas como medição de saúde sem validação. | Informar metodologia e limitações; evitar alegações de precisão clínica sem evidência. |
| Conteúdo DSM/diagnóstico diferencial | REQUIRES HUMAN/CLINICAL REVIEW | Pode induzir autodiagnóstico. | Garantir finalidade educativa e encaminhamento profissional. |

## 16. Required Manual Actions

1. Pelo Xcode, definir `CODE_SIGN_ENTITLEMENTS` de Release para `Neuremia/NeuremiaRelease.entitlements`.
2. Criar/adicionar `PrivacyInfo.xcprivacy` ao target principal com `UserDefaults` reason `CA92.1`; validar Archive.
3. Configurar `NeuremiaAPIBaseURL` Release com domínio HTTPS real e backend ativo para App Review.
4. Confirmar App ID, provisioning profile, HealthKit, HealthKit background delivery e Push production no Apple Developer.
5. Decidir produto final: local-only ou remoto. Alinhar UI, política, App Privacy, review notes e backend.
6. Migrar dados sensíveis de `UserDefaults` para armazenamento protegido/encriptado.
7. Implementar limpeza local completa em logout/troca de conta/exclusão, ou deixar explícito quando dados permanecem no dispositivo.
8. Substituir apagamento automático de SwiftData por migração segura.
9. Revisar conteúdo clínico, metodologia, escalas, riscos e disclaimers com responsável clínico/legal.
10. Executar Archive assinado em dispositivo/ambiente Xcode funcional e validar upload para App Store Connect/TestFlight.
11. Preencher App Privacy no App Store Connect com base na tabela deste relatório, após decisão sobre backend e sync.
12. Preparar demo account ou demo mode completo, com backend vivo, para App Review.

## 17. Tests Performed

| Validação | Comando/Ferramenta | Resultado |
|---|---|---|
| Build pelo Xcode MCP | `BuildProject` | PASS; build succeeded. |
| Warnings do build MCP | `GetBuildLog(severity: warning)` | PASS; nenhum warning retornado. |
| Lista do projeto | `xcodebuild -list -project Neuremia.xcodeproj` | PASS com warnings ambientais de CoreSimulator. |
| Build Debug explícito | `xcodebuild ... -configuration Debug ... build CODE_SIGNING_ALLOWED=NO` | FAIL/ENV; CoreSimulator/actool sem runtimes. |
| Build Release explícito | `xcodebuild ... -configuration Release ... build CODE_SIGNING_ALLOWED=NO` | FAIL/ENV; CoreSimulator/actool sem runtimes. |
| Archive Release explícito | `xcodebuild ... -configuration Release ... archive CODE_SIGNING_ALLOWED=NO` | FAIL/ENV; CoreSimulator/actool sem runtimes. |
| Testes unit/UI | Não executados | NOT TESTED; ambiente de Simulator indisponível. |
| Upload/TestFlight/App Store validation | Não executado | NOT TESTED. |
| Busca estática de permissões/secrets/placeholders | Xcode tools + shell grep | PARTIAL; app iOS coberto, backend analisado apenas como apoio. |

## 18. Remaining Warnings

| Severidade | Item | Observação |
|---|---|---|
| MEDIUM | `ENABLE_PREVIEWS = YES` em Release | Não bloqueia necessariamente, mas é configuração de desenvolvimento em Release. |
| MEDIUM | `COPY_PHASE_STRIP = NO` no Release project-level | Incomum para produção; revisar se símbolos/debug info estão adequados. |
| MEDIUM | HTTP permitido por lógica de URL configurável | Sem ATS exception, mas Release deveria exigir HTTPS explicitamente. |
| MEDIUM | Keychain com `WhenPasscodeSetThisDeviceOnly` | Bom para segurança, mas exige UX/erro claro em aparelhos sem senha. |
| LOW | Acessibilidade no checkbox legal | Label parece invertido: botão marcado anuncia estado oposto. |
| LOW | Launch screen mínima | Tecnicamente aceitável, mas revisar experiência visual se App Store screenshots/brand exigirem. |
| LOW | Repositório sujo | Muitas renomeações e mudanças preexistentes; estabilizar antes de release branch. |

## 19. Final Release Checklist

| Item | Estado |
|---|---|
| Xcode/SDK exigido atual | VERIFIED OK com SDK 26.5 local. |
| Bundle ID/App ID/App Store Connect | REQUIRES CONFIGURATION. |
| Release entitlements | FAIL até configurar no target. |
| Privacy Manifest | FAIL até adicionar e validar. |
| Backend Release | FAIL até substituir placeholder. |
| HealthKit capability/profile | REQUIRES CONFIGURATION. |
| Push production/profile | REQUIRES CONFIGURATION. |
| App Privacy labels | REVIEW REQUIRED. |
| Política de privacidade in-app | EXISTS, mas REVIEW REQUIRED. |
| Conta/exclusão de dados | REVIEW REQUIRED; backend e limpeza local precisam validação. |
| Dados sensíveis locais | FAIL; migrar/proteger antes de release. |
| Conteúdo clínico | REQUIRES HUMAN/CLINICAL REVIEW. |
| App icons | VERIFIED OK básico, 1024px presente. |
| Placeholders visíveis/de produção | FAIL por backend Release placeholder. |
| Testes em dispositivo físico Release | NOT TESTED. |
| Archive assinado | NOT TESTED. |
| Upload App Store Connect | NOT TESTED. |

DEBUG BUILD: PASS  
RELEASE BUILD: FAIL  
TESTS: NOT TESTED  
ARCHIVE: FAIL  
SIGNING: REQUIRES CONFIGURATION  
PRIVACY MANIFEST: FAIL  
APP PRIVACY DATA: REVIEW REQUIRED  
BLOCKERS REMAINING: 3  
CRITICAL ISSUES REMAINING: 3  
APP STORE READINESS: NOT READY
