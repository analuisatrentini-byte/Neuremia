//
//  PatientEvolutionView.swift
//  Neuremia
//

import SwiftUI
import Charts
import SwiftData

extension ContentView {
    var patientEvolutionPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            InsightsHeroCard(
                weeklyCheckInCount: weeklyCheckInCount,
                weeklyAverageMood: weeklyAverageMood,
                weeklyMoodDelta: weeklyMoodDelta,
                checkInStreak: gamificationManager.currentStreak
            )

            ExploreQuestStrip(
                completedCount: exploreCompletedCount,
                totalCount: ExploreMode.allCases.count,
                selectedMode: selectedExploreMode,
                selectMode: { selectedExploreMode = $0 },
                startCheckIn: { selectedPatientPage = .diary }
            )

            switch selectedExploreMode {
            case .now:
                exploreNowSection
            case .trends:
                exploreTrendsSection
            case .history:
                exploreHistorySection
            }
        }
    }

    var exploreCompletedCount: Int {
        [
            !sortedCheckIns.isEmpty,
            sortedCheckIns.count >= 2 || !assessments.isEmpty,
            !filteredCheckIns.isEmpty || !filteredAssessments.isEmpty || !filteredActiveAlerts.isEmpty
        ].filter { $0 }.count
    }

    @ViewBuilder
    var exploreNowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExploreSectionHeader(icon: "bolt.heart.fill", title: "Sinais de agora", subtitle: "O essencial para decidir o próximo passo.")
            EarlyDetectionBaselineBubble(checkIns: sortedCheckIns)
            NeuremiaRiskSignatureCard(signature: neuremiaRiskSignature)
            PatientFeedbackCard(summary: summary, canSave: canSaveClinicalData)
            SelfSignalHistoryCard(alerts: selfSignalAlerts)
        }
    }

    @ViewBuilder
    var exploreTrendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExploreSectionHeader(icon: "chart.line.uptrend.xyaxis", title: "Tendências", subtitle: "Padrões recentes e missões de autocuidado.")
            PatientEvolutionCard(
                checkIns: sortedCheckIns,
                currentMood: mood,
                currentAnxiety: anxiety,
                currentIrritability: irritability,
                currentSleep: sleepHours
            )
            SimplePatternDashboardCard(
                checkIns: sortedCheckIns,
                currentSteps: Double(healthSteps)
            )
            WeeklyMoodCalendarCard(checkIns: sortedCheckIns)
            WeekdayPatternCard(checkIns: sortedCheckIns)
            PatientPatternInsightCard(
                checkIns: sortedCheckIns,
                medicationPlans: medicationPlans,
                summary: summary
            )
            CausalInsightsCard(checkIns: sortedCheckIns)
            MonthlyMoodCalendarCard(checkIns: sortedCheckIns)
            MedicationTrackerCard(
                medicationStatus: medicationStatus,
                adherence: summary.medicationAdherence,
                sideEffects: sideEffects,
                checkIns: sortedCheckIns
            )
            CircadianStabilityCard(
                sleepHours: sleepHours,
                averageSleep: summary.averageSleep,
                checkInCount: summary.analyzedCheckInCount
            )
            RobustBiometricBaselineCard(
                checkIns: sortedCheckIns,
                currentHRV: ppgManager.hrv,
                globalHRVBaseline: hrvBaseline,
                hrvContextData: hrvContextBaselinesData,
                currentSleepHours: healthSleepHours > 0 ? healthSleepHours : sleepHours,
                medicationTaken: isMedicationFullyTaken,
                ppgStress: ppgManager.isHeartRatePhysiologicallyValid ? ppgManager.stress : 0,
                activeTriggers: activeTriggerLabels
            )
        }
    }

    @ViewBuilder
    var exploreHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExploreSectionHeader(icon: "clock.arrow.circlepath", title: "Histórico", subtitle: "Busca, linha do tempo e contexto clínico.")
            EvolutionSearchFilterCard(
                query: $evolutionSearchQuery,
                filter: $evolutionFilter
            )
            ClinicalTimelineCard(
                checkIns: sortedCheckIns,
                medicationPlans: medicationPlans,
                appointmentDate: Date(timeIntervalSince1970: nextAppointmentAt),
                appointmentNote: nextAppointmentNote
            )
            YearMoodOverviewCard(checkIns: sortedCheckIns)
            DigitalPhenotypeCard(
                checkIns: sortedCheckIns,
                medicationPlans: medicationPlans,
                signature: neuremiaRiskSignature,
                ppgStress: ppgManager.stress,
                ppgQuality: ppgManager.signalQuality,
                voicePauseRatio: voiceManager.pauseRatio,
                typingSpeed: bodySignalTypingSpeed,
                healthSleepHours: healthSleepHours,
                healthSteps: healthSteps,
                healthHeartRate: healthHeartRate
            )
            CareFocusCard(selectedFocus: $selectedCareFocus)
            ClinicalPersonalizationCard(selectedFocus: selectedCareFocus)
            historySection
        }
    }

    var selfSignalAlerts: [ClinicalAlert] {
        activeAlerts.filter { $0.kind == ClinicalAlertKind.selfSignal.rawValue }
    }

    @MainActor
    func persistBaselineSelfSignalsIfNeeded(now: Date = Date()) {
        guard activeRole == .patient else { return }

        let baselineSummary = PersonalBaselineEngine.compute(from: checkIns, now: now)
        guard !baselineSummary.warmingUp else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var insertedAny = false

        for baseline in baselineSummary.baselines.prefix(5) {
            let monthlyDrift = baseline.driftPerDay * 30
            let concerningDrift = baseline.metric.higherIsWorse
                ? monthlyDrift >= 0.6
                : monthlyDrift <= -0.6
            guard baseline.status == .alert || concerningDrift else { continue }

            let title = "Sinal do seu baseline: \(baseline.metric.label)"
            let alreadyExists = alerts.contains { alert in
                alert.kind == ClinicalAlertKind.selfSignal.rawValue
                    && alert.title == title
                    && calendar.isDate(alert.date, inSameDayAs: today)
            }
            guard !alreadyExists else { continue }

            let message: String
            if baseline.status == .alert {
                message = "\(baseline.currentCopy). \(baseline.centerCopy). Isso é um desvio pessoal, não um diagnóstico."
            } else {
                let direction = monthlyDrift > 0 ? "subindo" : "caindo"
                message = "Sua linha de base de \(baseline.metric.label.lowercased()) vem \(direction) no último ciclo. Observe o padrão e ajuste o dia se necessário."
            }

            modelContext.insert(ClinicalAlert(
                date: now,
                level: .moderate,
                kind: .selfSignal,
                escalationTarget: .patientOnly,
                title: title,
                message: message
            ))
            insertedAny = true
        }

        if insertedAny {
            do {
                try modelContext.save()
            } catch {
                showToast("Não foi possível salvar sinal de baseline: \(error.localizedDescription)", level: .error)
            }
        }
    }

    // MARK: - Insights hero — computed vars da semana

    /// Contagem de check-ins nos últimos 7 dias corridos (não semana calendário).
    var weeklyCheckInCount: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return sortedCheckIns.filter { $0.date >= cutoff }.count
    }

    /// Média de humor dos últimos 7 dias. `nil` quando não há dados.
    var weeklyAverageMood: Double? {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let recent = sortedCheckIns.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0.0) { $0 + $1.mood } / Double(recent.count)
    }

    /// Delta do humor médio semana atual vs. anterior. `nil` quando alguma
    /// janela está vazia — sem comparação possível.
    var weeklyMoodDelta: Double? {
        let now = Date()
        let thisWeekCutoff = now.addingTimeInterval(-7 * 24 * 3600)
        let previousWeekCutoff = now.addingTimeInterval(-14 * 24 * 3600)

        let thisWeek = sortedCheckIns.filter { $0.date >= thisWeekCutoff }
        let previousWeek = sortedCheckIns.filter {
            $0.date >= previousWeekCutoff && $0.date < thisWeekCutoff
        }

        guard !thisWeek.isEmpty, !previousWeek.isEmpty else { return nil }

        let currentAvg = thisWeek.reduce(0.0) { $0 + $1.mood } / Double(thisWeek.count)
        let previousAvg = previousWeek.reduce(0.0) { $0 + $1.mood } / Double(previousWeek.count)
        return currentAvg - previousAvg
    }
}

struct ExploreQuestStrip: View {
    let completedCount: Int
    let totalCount: Int
    let selectedMode: ExploreMode
    let selectMode: (ExploreMode) -> Void
    let startCheckIn: () -> Void

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.neuroOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missões de exploração")
                        .font(.headline.weight(.bold))
                    Text("\(completedCount)/\(totalCount) áreas com dados")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: startCheckIn) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.neuroOrange)
                .accessibilityLabel("Fazer check-in")
            }

            ProgressView(value: progress)
                .tint(.neuroYellow)
                .accessibilityLabel("Progresso de exploração")
                .accessibilityValue("\(completedCount) de \(totalCount)")

            HStack(spacing: 8) {
                ForEach(ExploreMode.allCases) { mode in
                    Button {
                        selectMode(mode)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.subheadline.weight(.bold))
                            Text(mode.rawValue)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(selectedMode == mode ? Color.neuroYellow : Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(selectedMode == mode ? Color.neuroNavy : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Abrir \(mode.rawValue)")
                    .accessibilityAddTraits(selectedMode == mode ? [.isSelected] : [])
                }
            }
        }
        .panelStyle()
    }
}

struct ExploreSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.neuroOrange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SelfSignalHistoryCard: View {
    let alerts: [ClinicalAlert]

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(icon: "person.crop.circle.badge.exclamationmark", title: "Sinais pessoais")
                ForEach(alerts.prefix(5)) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.teal)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.title)
                                .font(.subheadline.weight(.semibold))
                            Text(alert.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .panelStyle()
        }
    }
}
