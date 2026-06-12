# Pendências de limpeza que exigem o Xcode (ou ação do usuário)

Esta lista foi gerada na Sprint 7. Os itens abaixo **não foram aplicados automaticamente** porque dependem de operações que modificariam `NeuroFlow.xcodeproj/project.pbxproj` com o Xcode aberto, ou são operações destrutivas no histórico do git que exigem sua confirmação explícita.

---

## 1. Apagar `NeuroFlow/NeuroFlow/Item.swift` (stub vazio)

O arquivo só contém um comentário dizendo que o template SwiftData foi substituído por `ClinicalModels.swift`. Está adicionado ao target NeuroFlow mas não exporta nada.

**Como remover:**
1. No Xcode, navegador esquerdo → expandir `NeuroFlow` (grupo) → clicar em `Item.swift`.
2. Apertar Delete → escolher **Move to Trash**.
3. Build & Run para confirmar que nada quebra (nada quebra; já validei via grep que ninguém importa).

---

## 2. Resolver duplicidade `ClinicalModels.swift` / `ClinicalAnalysis.swift`

O git status mostra:
```
AD NeuroFlow/ClinicalAnalysis.swift
AD NeuroFlow/ClinicalModels.swift
```

Isso significa que esses arquivos foram **adicionados** ao subdiretório `NeuroFlow/NeuroFlow/` (junto com `ContentView.swift`) e depois **deletados** do disco. O `project.pbxproj` aponta para os reais em `/Users/.../NeuroFlow/` (raiz), que são os que estão sendo compilados.

**Como resolver:**
1. No terminal:
   ```bash
   cd /Users/analuisabittencourt/Desktop/NeuroFlow
   git rm --cached NeuroFlow/ClinicalAnalysis.swift NeuroFlow/ClinicalModels.swift 2>/dev/null
   ```
2. Commitar a limpeza. O git status vai parar de mostrar essas linhas.
3. Confirmar que os arquivos certos estão em `/Users/.../NeuroFlow/ClinicalModels.swift` e `ClinicalAnalysis.swift` (raiz do projeto), como aponta o `pbxproj`.

---

## 3. Localização (`Localizable.strings`)

Todas as strings de UI estão hardcoded em português dentro de `ContentView.swift`. Para internacionalizar:

1. No Xcode: File → New → File... → **Strings File** (chame de `Localizable.strings`).
2. Adicionar ao target NeuroFlow.
3. No File Inspector, clicar em **Localize...** → adicionar `Portuguese (Brazil)` e (se quiser) `English`.
4. Extrair strings via `genstrings`:
   ```bash
   cd /Users/analuisabittencourt/Desktop/NeuroFlow
   find . -name "*.swift" -not -path "*/Products/*" -not -path "*/.venv/*" | xargs genstrings -o NeuroFlow/NeuroFlow/Base.lproj
   ```
5. Substituir os `Text("...")` por `Text(LocalizedStringKey("..."))` ou `Text("key", comment: "...")`. SwiftUI faz o lookup automático.

> Não fiz porque criar `Localizable.strings` exige adicionar ao `project.pbxproj`, e o Xcode aberto torna essa edição arriscada (foi explicitamente bloqueado por hook na Sprint 3).

---

## 4. `git filter-repo` para purgar segredos e binários do histórico

O `docker-compose.yml` versionado tinha `NEUROFLOW_FIELD_ENCRYPTION_KEY` real (corrigido na Sprint 1, mas continua no histórico do git). `Backend/neuroflow.db` (147 KB) e `Backend/.venv/` ainda estão no histórico se algum commit antigo os adicionou.

**⚠️ Esta é uma operação destrutiva que reescreve a história e exige re-push forçado.** Coordene com qualquer colaborador antes.

```bash
# Backup primeiro
cd /Users/analuisabittencourt/Desktop
cp -R NeuroFlow NeuroFlow-backup-before-filter-repo

# Instalar git-filter-repo
pip install git-filter-repo

# Aplicar
cd NeuroFlow
git filter-repo \
  --invert-paths \
  --path Backend/neuroflow.db \
  --path Backend/.venv \
  --path Backend/app/__pycache__

# Verificar que sumiu
git log --all --full-history -- Backend/neuroflow.db   # deve estar vazio

# Push forçado para o remoto (se já tiver remoto)
git push --force --all
git push --force --tags
```

**Adicional:** rotacionar `NEUROFLOW_FIELD_ENCRYPTION_KEY` e `NEUROFLOW_SECRET_KEY` em qualquer ambiente que tenha usado as antigas (mesmo após purga do git, considere as antigas comprometidas).

---

## 5. Renomeação consistente PT/EN (opcional)

A base mistura `paciente`/`patient`, `medico`/`clinician`. Decidir um idioma para nomes de tipos e variáveis ajuda a evitar bugs por typo. Se for fazer:

- **Recomendo manter EN** para tipos/variáveis (já é maioria: `PatientProfile`, `DailyCheckIn`, `BackendAuthClient`, etc.) e PT só nas strings de UI.
- Casos a renomear: `medicationName` (já EN), `careTeam*` (já EN). Maior dor: comentários inline misturados.

Refator amplo demais para fazer em uma sessão sem testes E2E rodando. Pode ser feito incremental conforme tocar cada área.

---

## 6. Acessibilidade completa

A Sprint 4 fez passe focado em `MoodSignalPill`, `StatBadge`, `caregiverManagementCard`, botão de salvar e botões LGPD. **Não cobertos:**

- `RiskSummaryCard`, `TextRiskCard`, `NeuroFlowRiskSignatureCard` (ainda dependem só de cor para severidade).
- Os ~70 cards restantes em `patientEvolutionPage` e `doctorDashboard`.
- Suporte a `Dynamic Type Extra Extra Large` — vários `.lineLimit(1)` ainda cortam textos descritivos.

Passe completo levaria 1-2 dias dedicados. Use o Accessibility Inspector do Xcode para auditar.

---

## 7. Migrar `datetime.utcnow()` → `datetime.now(timezone.utc)` no backend

Em `Backend/app/models.py` e `Backend/app/main.py`. Python 3.14 emite `DeprecationWarning` para `utcnow()`. Trivial mas envolve ~10 substituições e validar que nenhum timestamp é comparado a um naive datetime depois.

---

## 8. Quebrar `ContentView.swift` em vários arquivos (Sprint 3 parcial)

Plano original previa 80 arquivos via `Theme.swift`, `BiometricManagers.swift`, etc. **Foi bloqueado por hook** porque exige editar `project.pbxproj` com Xcode aberto.

**Como fazer pelo Xcode:**
1. Fechar o app NeuroFlow rodando no simulador (se houver).
2. No Xcode: File → New → File... → Swift File → nome `Theme.swift`, target NeuroFlow.
3. Recortar (do `ContentView.swift`) as `private extension Color`/`private extension UIColor` e o `private extension View { func panelStyle() }` para o `Theme.swift`, trocando `private extension` por `extension`.
4. Build & Run.
5. Repetir para `BiometricManagers.swift` (PPGCameraManager + VoiceSignalManager).
6. Outras extrações ficam mais fáceis depois disso.
