//
//  ClinicalScalesView.swift
//  NeuroFlow
//

import SwiftUI
import Charts

extension ContentView {
    var scalesDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "heart.text.square", title: "Check-up do bem-estar")

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

            VStack(alignment: .leading, spacing: 14) {
                Text(selectedScale.focus)
                    .font(.headline)

                Text("Sugestão: registre \(summary.cadence.lowercased()), ajustando conforme sentir necessidade.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(selectedScale.administrationNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // P1-5 (UX): ScaleResultCard movido para depois das questões.
                // Antes o resultado ("Grave") aparecia antes de o paciente
                // responder qualquer item — ancoragem cognitiva que pode
                // influenciar as respostas. Agora o score atualiza em tempo
                // real conforme o paciente responde, e fica visível no final.
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
                    Label("Salvar \(selectedScale.rawValue)", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveClinicalData)

                // P1-2: status migrado para toast central.
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
                TextRiskCard(title: "Classificação textual longitudinal", assessment: summary.textAssessment)
                ClinicianPopulationRiskCard(signature: neuroFlowRiskSignature, alerts: activeAlerts, checkIns: sortedCheckIns, remotePatients: clinicianPatients)
                ClinicianPreConsultInsightCard(
                    summary: summary,
                    checkIns: sortedCheckIns,
                    assessments: sortedAssessments,
                    medicationPlans: medicationPlans,
                    signature: neuroFlowRiskSignature
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
