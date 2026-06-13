//
//  ContentView+PatientRoot.swift
//  NeuroFlow
//

import SwiftUI

extension ContentView {
    var toolbarContent: some ToolbarContent {
        // P1-3 (UX): troca de papel direto na toolbar, sem abrir Settings.
        // Ícone badge mostra o papel ativo — clínico vê "Médico", paciente vê
        // "Paciente". ConfirmationDialog reutiliza o mecanismo já existente.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                roleChangePending = activeRole == .clinician ? .patient : .clinician
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: activeRole == .clinician ? "stethoscope" : "person.fill")
                        .font(.subheadline)
                    Text(activeRole == .clinician ? "Médico" : "Paciente")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .tint(.primary)
            .accessibilityLabel("Perfil ativo: \(activeRole == .clinician ? "Médico" : "Paciente"). Toque para alternar.")
        }
        // Crise sempre acessível (M10) — botão vermelho próximo do polegar
        // direito em qualquer aba, abre o CrisisSupportCard na hora.
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingCrisisSheet = true
            } label: {
                Image(systemName: "cross.case.fill")
            }
            .tint(.red)
            .accessibilityLabel("Apoio em crise")
            .accessibilityHint("Abre contatos do CVV, SAMU e seu contato de segurança.")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .overlay(alignment: .topTrailing) {
                        if offlineSyncQueue.count > 0 {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -3)
                        }
                    }
            }
            // Cor neutra (Sprint 21) — settings é navegação secundária, não
            // ação primária. SOS continua vermelho para destacar urgência.
            .tint(.primary)
            .accessibilityLabel(offlineSyncQueue.count > 0
                ? "Configurações — \(offlineSyncQueue.count) item(ns) pendente(s) de sincronização"
                : "Configurações")
        }
    }

    var appBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color.neuroYellow.opacity(0.18),
                Color.orange.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }


}
