//
//  ClinicalScalesView.swift
//  Neuremia
//

import SwiftUI

extension ContentView {
    var scalesDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "heart.text.square", title: "Check-up do bem-estar")

            AutomaticWellbeingCheckupCard(
                results: automaticCheckupResults,
                statusMessage: scaleStatusMessage,
                canSave: canSaveClinicalData,
                save: saveAutomaticCheckups
            )

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Escala", selection: $selectedScale) {
                        ForEach(ScaleKind.allCases) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedScale) { _, _ in
                        ensureAnswers(for: selectedScale)
                        scaleStatusMessage = ""
                    }

                    Text(selectedScale.focus)
                        .font(.headline)

                    Label(selectedScale.administrationNote, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(selectedScale.questions.indices, id: \.self) { index in
                        ScaleQuestionRow(
                            number: index + 1,
                            question: selectedScale.questions[index],
                            range: selectedScale.answerRange(for: index),
                            answer: answerBinding(for: selectedScale, index: index)
                        )
                    }

                    ScaleResultCard(
                        scale: selectedScale,
                        score: selectedScaleScore,
                        interpretation: selectedScaleInterpretation,
                        hasCriticalPHQ9Answer: hasCriticalPHQ9Answer
                    )

                    Button(action: saveScaleAssessment) {
                        Label("Salvar aplicação formal \(selectedScale.rawValue)", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSaveClinicalData)
                }
                .padding(.top, 10)
            } label: {
                Label("Aplicação formal das escalas", systemImage: "list.clipboard")
                    .font(.headline)
            }
            .panelStyle()

            recentScalesSection
        }
    }

    var doctorDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "stethoscope", title: "Dashboard médico")

            if !canViewClinicianData {
                AccessGateCard(
                    activeRole: activeRole,
                    hasSharingConsent: patients.first?.shareWithClinician == true
                )
            } else {
                clinicianPatientsSection
                clinicianSentInvitesSection
                RiskSummaryCard(summary: summary)
                TemporalRiskPredictionCard(prediction: summary.temporalPrediction)
                EpisodePipelineCard(forecasts: summary.episodeForecasts)
                TextRiskCard(title: "Classificação textual longitudinal", assessment: summary.textAssessment)
                ClinicalDailyDigestCard(digest: summary.clinicalDigest)
                ClinicianPopulationRiskCard(signature: neuremiaRiskSignature, alerts: activeAlerts.filter { $0.kind != ClinicalAlertKind.selfSignal.rawValue }, checkIns: sortedCheckIns, remotePatients: clinicianPatients)
                ClinicianPreConsultInsightCard(
                    summary: summary,
                    checkIns: sortedCheckIns,
                    assessments: sortedAssessments,
                    medicationPlans: medicationPlans,
                    signature: neuremiaRiskSignature
                )

                longitudinalTrendsSection

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(summary.signals, id: \.self) { signal in
                        ClinicalSignal(icon: "chart.line.uptrend.xyaxis", title: signal, description: "Sinal calculado a partir dos registros diários, escalas e análise textual.")
                    }
                }
                .panelStyle()

                alertsSection
                reportSection
            }
        }
    }

    var longitudinalTrendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "chart.xyaxis.line", title: "Análise longitudinal")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                TrendMetricCard(
                    title: "Humor",
                    icon: "face.smiling",
                    firstValue: summary.firstMood,
                    latestValue: summary.latestMood,
                    trend: summary.moodTrend,
                    unit: "",
                    higherIsBetter: true
                )

                TrendMetricCard(
                    title: "Ansiedade",
                    icon: "waveform.path.ecg",
                    firstValue: summary.firstAnxiety,
                    latestValue: summary.latestAnxiety,
                    trend: summary.anxietyTrend,
                    unit: "",
                    higherIsBetter: false
                )

                TrendMetricCard(
                    title: "Sono",
                    icon: "moon.zzz",
                    firstValue: summary.firstSleep,
                    latestValue: summary.latestSleep,
                    trend: summary.sleepTrend,
                    unit: "h",
                    higherIsBetter: true
                )

                StatBadge(title: "Registros analisados", value: "\(summary.analyzedCheckInCount)", icon: "calendar")
            }
        }
        .panelStyle()
    }


}
