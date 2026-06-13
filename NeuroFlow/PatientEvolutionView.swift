//
//  PatientEvolutionView.swift
//  NeuroFlow
//

import SwiftUI
import Charts

extension ContentView {
    var patientEvolutionPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(icon: "chart.line.uptrend.xyaxis", title: "Evolução")

            EvolutionSearchFilterCard(
                query: $evolutionSearchQuery,
                filter: $evolutionFilter
            )

            // ── Zona 1: Agora ────────────────────────────────────────────────
            // S5 (UX): hierarquia visual por zona — risco e insight urgente
            // aparecem sem scroll, para o usuário ver o que importa primeiro.
            VStack(alignment: .leading, spacing: 4) {
                Text("Agora")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                NeuroFlowRiskSignatureCard(signature: neuroFlowRiskSignature)
                PatientFeedbackCard(summary: summary, canSave: canSaveClinicalData)
            }

            // ── Zona 2: Últimos 30 dias ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("Últimos 30 dias")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                PatientEvolutionCard(
                    checkIns: sortedCheckIns,
                    currentMood: mood,
                    currentAnxiety: anxiety,
                    currentIrritability: irritability,
                    currentSleep: sleepHours
                )
                PatientPatternInsightCard(
                    checkIns: sortedCheckIns,
                    medicationPlans: medicationPlans,
                    summary: summary
                )
                AppointmentEventCard(
                    appointmentDate: nextAppointmentDateBinding,
                    note: $nextAppointmentNote
                )
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
            }

            // ── Zona 3: Histórico completo ───────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("Histórico completo")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

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
                    signature: neuroFlowRiskSignature,
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
    }
}
