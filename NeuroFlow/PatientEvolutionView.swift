//
//  PatientEvolutionView.swift
//  NeuroFlow
//

import SwiftUI
import Charts

extension ContentView {
    var patientEvolutionPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "chart.line.uptrend.xyaxis", title: "Evolução")

            EvolutionSearchFilterCard(
                query: $evolutionSearchQuery,
                filter: $evolutionFilter
            )

            // P1-1 (UX): PatientFeedbackCard removido daqui — já aparece na
            // aba "Hoje". Manter nas duas abas criava duplicação confusa sem
            // distinguir "status de hoje" de "resumo da semana". O
            // NeuroFlowRiskSignatureCard já comunica o risco longitudinal.
            NeuroFlowRiskSignatureCard(signature: neuroFlowRiskSignature)
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
            ClinicalTimelineCard(
                checkIns: sortedCheckIns,
                medicationPlans: medicationPlans,
                appointmentDate: Date(timeIntervalSince1970: nextAppointmentAt),
                appointmentNote: nextAppointmentNote
            )
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
            MonthlyMoodCalendarCard(checkIns: sortedCheckIns)
            YearMoodOverviewCard(checkIns: sortedCheckIns)
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
            CareFocusCard(selectedFocus: $selectedCareFocus)
            ClinicalPersonalizationCard(selectedFocus: selectedCareFocus)

            historySection
        }
    }


}
