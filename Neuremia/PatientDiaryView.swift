//
//  PatientDiaryView.swift
//  Neuremia
//

import SwiftUI
import HealthKit

extension ContentView {
    var patientDiaryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "book.closed", title: "Diário")
            TodayMoodOverviewCard(
                mood: mood,
                anxiety: anxiety,
                sleepHours: sleepHours,
                medicationTaken: isMedicationFullyTaken
            )
            PatientFeedbackCard(summary: summary, canSave: canSaveClinicalData)
            DailyRecommendationCard(
                recommendation: adjustedDailyRecommendation,
                log: todayRecommendationLog,
                responseProfile: currentRecommendationResponseProfile,
                canSave: canSaveClinicalData,
                markCompleted: markTodayRecommendationCompleted
            )
            OfflineSyncStatusCard(
                pendingCount: offlineSyncQueue.count,
                lastStatus: lastSyncStatus,
                localOnlyMode: DataResidencyPolicy.localOnlyMode,
                retrySync: retryPendingSync
            )

            // M2 (UX-P0): diário dividido em 3 seções recolhíveis para reduzir
            // carga cognitiva. Pacientes com baixa energia podem expandir apenas
            // o que precisam preencher, sem rolar uma tela única interminável.
            VStack(alignment: .leading, spacing: 16) {

                // ── Seção 1: Como você está? ─────────────────────────────────
                DisclosureGroup(isExpanded: $diarySection1Expanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        MoodWheelCard(mood: $mood, anxiety: $anxiety, energy: $energy)

                        Text("Toque no estado que mais combina com hoje")
                            .font(.headline)

                        // Campos essenciais — sempre visíveis. Humor, Ansiedade
                        // e Sono são os 3 preditores mais relevantes clinicamente
                        // e os que menos exigem reflexão prolongada.
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            VisualMetricPicker(title: "Humor", icon: "face.smiling", value: $mood, options: [
                                MetricOption(label: "Muito difícil", value: 1, color: .red),
                                MetricOption(label: "Difícil", value: 2, color: .orange),
                                MetricOption(label: "Regular", value: 3, color: .neuroYellow),
                                MetricOption(label: "Bem", value: 4, color: .green),
                                MetricOption(label: "Ótimo", value: 5, color: .green)
                            ])

                            VisualMetricPicker(title: "Ansiedade", icon: "waveform.path.ecg", value: $anxiety, options: [
                                MetricOption(label: "Tranquilo", value: 1, color: .green),
                                MetricOption(label: "Leve", value: 2, color: .green),
                                MetricOption(label: "Média", value: 3, color: .neuroYellow),
                                MetricOption(label: "Alta", value: 4, color: .orange),
                                MetricOption(label: "Pico", value: 5, color: .red)
                            ])

                            VisualMetricPicker(title: "Sono", icon: "moon.zzz", value: $sleepHours, options: [
                                MetricOption(label: "<4h", value: 4, color: .red),
                                MetricOption(label: "5h", value: 5, color: .orange),
                                MetricOption(label: "6h", value: 6, color: .neuroYellow),
                                MetricOption(label: "7h", value: 7, color: .green),
                                MetricOption(label: "8h+", value: 8, color: .green)
                            ], suffix: "h")
                        }

                        // Campos opcionais — expandidos apenas quando o paciente
                        // quiser registrar com mais detalhe.
                        DisclosureGroup(isExpanded: $diarySection1DetailsExpanded) {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                VisualMetricPicker(title: "Energia", icon: "bolt", value: $energy, options: [
                                    MetricOption(label: "Exausto", value: 1, color: .red),
                                    MetricOption(label: "Baixa", value: 2, color: .orange),
                                    MetricOption(label: "Normal", value: 3, color: .neuroYellow),
                                    MetricOption(label: "Boa", value: 4, color: .green),
                                    MetricOption(label: "Alta", value: 5, color: .green)
                                ])

                                VisualMetricPicker(title: "Irritabilidade", icon: "exclamationmark.bubble", value: $irritability, options: [
                                    MetricOption(label: "Calmo", value: 1, color: .green),
                                    MetricOption(label: "Leve", value: 2, color: .green),
                                    MetricOption(label: "Média", value: 3, color: .neuroYellow),
                                    MetricOption(label: "Alta", value: 4, color: .orange),
                                    MetricOption(label: "Pico", value: 5, color: .red)
                                ])

                                VisualMetricPicker(title: "Apetite", icon: "fork.knife", value: $appetite, options: [
                                    MetricOption(label: "Muito baixo", value: 1, color: .red),
                                    MetricOption(label: "Baixo", value: 2, color: .orange),
                                    MetricOption(label: "Normal", value: 3, color: .neuroYellow),
                                    MetricOption(label: "Alto", value: 4, color: .orange),
                                    MetricOption(label: "Voraz", value: 5, color: .red)
                                ])

                                // P2-7 (UX): "Não se aplica" evita ruído de dados
                                // com valor default 3 para quem ignora o campo.
                                VisualMetricPicker(
                                    title: "Libido", icon: "heart", value: $libido,
                                    options: [
                                        MetricOption(label: "Muito baixa", value: 1, color: .red),
                                        MetricOption(label: "Baixa", value: 2, color: .orange),
                                        MetricOption(label: "Normal", value: 3, color: .neuroYellow),
                                        MetricOption(label: "Alta", value: 4, color: .orange),
                                        MetricOption(label: "Muito alta", value: 5, color: .red)
                                    ],
                                    skipLabel: "Não se aplica",
                                    skipValue: 0.0
                                )
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: diarySection1DetailsExpanded ? "minus.circle.fill" : "plus.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.neuroOrange)
                                Text(diarySection1DetailsExpanded ? "Menos detalhes" : "Mais detalhes")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.neuroOrange)
                            }
                            .padding(.top, 4)
                            .accessibilityLabel(diarySection1DetailsExpanded
                                ? "Recolher campos de Energia, Irritabilidade, Apetite e Libido"
                                : "Expandir campos de Energia, Irritabilidade, Apetite e Libido")
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Como você está?", systemImage: "face.smiling")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Divider()

                // ── Seção 2: Segurança e medicação ───────────────────────────
                DisclosureGroup(isExpanded: $diarySection2Expanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        DailySafetyChoices(
                            medicationStatus: $medicationStatus,
                            safetyStatus: $safetyStatus
                        )

                        MedicationPlanCard(
                            medicationName: $medicationName,
                            medicationDose: $medicationDose,
                            medicationSchedule: $medicationSchedule,
                            medicationPrescription: $medicationPrescription,
                            medicationChangeNote: $medicationChangeNote,
                            medicationPlans: medicationPlans,
                            addMedication: addMedicationPlan,
                            removeMedication: removeMedicationPlan
                        )

                        CustomSymptomCard(
                            symptomName: $customSymptomName,
                            symptomValue: $customSymptomValue,
                            symptoms: customSymptoms,
                            addSymptom: addCustomSymptom,
                            removeSymptom: removeCustomSymptom
                        )
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Segurança e medicação", systemImage: "pills")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Divider()

                // ── Seção 3: Texto livre e gatilhos ──────────────────────────
                DisclosureGroup(isExpanded: $diarySection3Expanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        // S10 (UX): TriggerMapCard movido para dentro desta seção
                        // — o nome "Texto livre e gatilhos" prometia gatilhos mas
                        // não os entregava aqui, criando inconsistência silenciosa.
                        TriggerMapCard(
                            alcoholTrigger: $alcoholTrigger,
                            poorSleepTrigger: $poorSleepTrigger,
                            stressTrigger: $stressTrigger,
                            conflictTrigger: $conflictTrigger,
                            routineChangeTrigger: $routineChangeTrigger,
                            menstrualTrigger: $menstrualTrigger,
                            customTriggerText: $customTriggerText,
                            customTriggers: $customTriggers,
                            checkIns: sortedCheckIns
                        )
                        LabeledTextEditor(title: "Efeitos colaterais", systemImage: "pills", placeholder: "Ex.: sonolência, náusea, agitação", text: $sideEffects)
                            .onChange(of: sideEffects) { _, v in if v.count > 2000 { sideEffects = String(v.prefix(2000)) } }
                        LabeledTextEditor(title: "Pensamentos do dia", systemImage: "bubble.left.and.text.bubble.right", placeholder: "Ex.: pensamentos que apareceram várias vezes hoje", text: $automaticThoughts)
                            .onChange(of: automaticThoughts) { _, v in if v.count > 2000 { automaticThoughts = String(v.prefix(2000)) } }
                        LabeledTextEditor(title: "Meu diário", systemImage: "square.and.pencil", placeholder: "Escreva como foi seu dia, sono, acontecimentos e o que quiser lembrar depois.", text: $journalEntry)
                            .onChange(of: journalEntry) { _, newValue in
                                if newValue.count > 5000 { journalEntry = String(newValue.prefix(5000)) }
                                updateTypingSignals(text: newValue)
                            }

                        TextRiskCard(title: "Sinais percebidos no diário", assessment: currentTextAssessment, patientStyle: true)
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Texto livre e gatilhos", systemImage: "square.and.pencil")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .panelStyle()
            // Cards de ferramentas (SafetyPlanEditor, Engagement, Psychoeducation,
            // DSM5Foundation, ScaleAccess, MonthlyReport, ReportExport) foram
            // movidos para a tab "Ferramentas" no Sprint 19. Mantemos só
            // AutomaticWellbeingCheckup no Diário porque ele depende
            // diretamente do check-in que o paciente acabou de preencher.
            AutomaticWellbeingCheckupCard(
                results: automaticCheckupResults,
                statusMessage: scaleStatusMessage,
                canSave: canSaveClinicalData,
                save: saveAutomaticCheckups
            )

            if hasCriticalSafetyRisk || currentTextAssessment.level == .high {
                CrisisSupportCard(
                    safetyContact: safetyContact,
                    warningSigns: safetyWarningSigns,
                    strategies: safetyStrategies,
                    protocolSummary: currentCrisisProtocol
                )
            }
        }
    }

    var patientBodySignalsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "waveform.path.ecg", title: "Sinais do corpo")

            BodySignalsIntroCard()

            if !biometricConsentAccepted {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Consentimento necessário", systemImage: "hand.raised.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text("A coleta de sinais biométricos (frequência cardíaca, variabilidade de voz) requer seu consentimento específico. Esses dados são processados localmente no aparelho e não são enviados ao servidor sem sua autorização explícita.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        biometricConsentAccepted = true
                        biometricConsentGrantedAt = Date().timeIntervalSince1970
                        // M4 — sync grant with backend consent registry when remote sync is enabled.
                        if DataResidencyPolicy.remoteSyncEnabled && !authToken.isEmpty {
                            Task { try? await BackendAuthClient.grantBiometricConsent(token: authToken) }
                        }
                    } label: {
                        Text("Concordar e ativar sinais biométricos")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityHint("Consente com a coleta local de sinais de câmera e microfone para análise de bem-estar.")
                }
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
            BodySignalsReadingCard(
                heartRate: ppgManager.heartRate,
                hrv: ppgManager.hrv,
                respiration: ppgManager.respiration,
                perfusion: ppgManager.perfusion,
                stress: ppgManager.stress,
                quality: ppgManager.signalQuality,
                status: ppgManager.status,
                isMeasuring: ppgManager.isMeasuring,
                start: ppgManager.start,
                stop: ppgManager.stop
            )

            // Sprint 25: detalhes técnicos colapsados por padrão. Usuários
            // curiosos podem expandir; quem só quer o essencial não é
            // sobrecarregado com jargão (latência de digitação, jitter, etc).
            DisclosureGroup(isExpanded: $isShowingBodySignalsTechnicalDetails) {
                VStack(alignment: .leading, spacing: 16) {
                    BodySignalsBehaviorCard(
                        typingLatency: bodySignalTypingLatency,
                        typingSpeed: bodySignalTypingSpeed,
                        interactionCount: bodySignalInteractionCount,
                        sessionMinutes: Date().timeIntervalSince(appSessionStartedAt) / 60,
                        voiceAverage: voiceManager.averagePower,
                        voicePauseRatio: voiceManager.pauseRatio,
                        voiceVariability: voiceManager.variability,
                        voicePitch: voiceManager.fundamentalFrequency,
                        voicePitchVariability: voiceManager.pitchVariability,
                        voiceSyllableEnergy: voiceManager.syllableEnergy,
                        voiceRhythm: voiceManager.rhythm,
                        voiceStatus: voiceManager.status,
                        isRecording: voiceManager.isRecording,
                        startVoice: voiceManager.start,
                        stopVoice: voiceManager.stop
                    )

                    CombinedBodySignalCard(
                        ppgStress: ppgManager.stress,
                        signalQuality: ppgManager.signalQuality,
                        typingSpeed: bodySignalTypingSpeed,
                        voicePauseRatio: voiceManager.pauseRatio,
                        voiceVariability: voiceManager.variability,
                        sleepHours: healthSleepHours > 0 ? healthSleepHours : sleepHours,
                        steps: healthSteps
                    )
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.neuroNavy)
                        .frame(width: 32, height: 32)
                        .background(Color.neuroYellow)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detalhes técnicos das medições")
                            .font(.subheadline.weight(.semibold))
                        Text(isShowingBodySignalsTechnicalDetails ? "Toque para esconder" : "Voz, digitação e combinação dos sinais")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Expande ou recolhe as métricas avançadas de comportamento e voz")
            }
            .panelStyle()

            BodySignalsSourcesCard(
                sleepHours: healthSleepHours,
                steps: healthSteps,
                heartRate: healthHeartRate,
                activeEnergy: healthActiveEnergy,
                hrv: healthHRV,
                restingHeartRate: healthKitPipelineStore.snapshots.first(where: { $0.dayKey == DailyCheckIn.dayKey(for: Date()) })?.restingHeartRate ?? 0,
                healthKitSnapshots: healthKitPipelineStore.snapshots,
                lastSyncAt: lastHealthKitSyncAt,
                syncHealth: {
                    Task {
                        await requestHealthKitAccessAndSync()
                    }
                }
            )

            BodySignalsLimitationsCard()

            Button(role: .destructive) {
                ppgManager.stop()
                voiceManager.stop()
                biometricConsentAccepted = false
            } label: {
                Label("Revogar consentimento de biossensores", systemImage: "hand.raised.slash.fill")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            } // end biometricConsentAccepted else
        }
    }


}
