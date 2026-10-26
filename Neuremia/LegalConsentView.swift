//
//  LegalConsentView.swift
//  Neuremia
//
//  Presented at first launch (onboarding) and whenever LegalVersion.current
//  changes after an app update. The user must explicitly accept both the
//  Terms of Use and the Privacy Policy before accessing the app.
//  LGPD Art. 7 I + Art. 9 §1: consentimento livre, informado, inequívoco.
//

import SwiftUI

// MARK: - Full-text document reader

struct LegalDocumentView: View {
    let title: String
    let documentText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(documentText)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}

enum LegalDocument: Identifiable {
    case terms
    case privacy

    var id: String { title }

    var title: String {
        switch self {
        case .terms:
            return "Termos de Uso"
        case .privacy:
            return "Política de Privacidade"
        }
    }

    var text: String {
        switch self {
        case .terms:
            return neuremiaTermsOfUse
        case .privacy:
            return neuremiaPrivacyPolicy
        }
    }
}

// MARK: - Consent gate

/// Full-screen gate shown at first launch or after a policy update.
/// Dismisses only when the user taps "Li e aceito". The backing
/// @AppStorage flag is written by the CALLER after this view returns.
struct LegalConsentView: View {
    /// Called when the user accepts. The caller should persist the acceptance
    /// version and dismiss this view.
    let onAccept: () -> Void

    @State private var termsChecked = false
    @State private var privacyChecked = false
    @State private var activeDocument: LegalDocument?

    private var canAccept: Bool { termsChecked && privacyChecked }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // ── Header ──────────────────────────────────────────────
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "doc.badge.gearshape.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.neuroOrange)
                        Text("Termos e Privacidade")
                            .font(.title2.weight(.bold))
                        Text(
                            "Para usar o Neuremia, leia e aceite os documentos abaixo. " +
                            "Seus dados clínicos são sensíveis e seu consentimento é " +
                            "obrigatório pela LGPD."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // ── Checkboxes ───────────────────────────────────────────
                    VStack(spacing: 0) {
                        consentRow(
                            isChecked: $termsChecked,
                            label: "Li e aceito os",
                            linkLabel: "Termos de Uso",
                            action: { activeDocument = .terms }
                        )
                        Divider().padding(.leading, 48)
                        consentRow(
                            isChecked: $privacyChecked,
                            label: "Li e aceito a",
                            linkLabel: "Política de Privacidade",
                            action: { activeDocument = .privacy }
                        )
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                    // ── Summary bullets ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("O que isso significa:")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        bulletPoint(icon: "lock.fill", color: .green,
                            text: "Seus dados clínicos são criptografados e nunca vendidos a terceiros.")
                        bulletPoint(icon: "person.badge.minus", color: .blue,
                            text: "Profissionais só acessam seus dados se VOCÊ aceitar o convite deles.")
                        bulletPoint(icon: "arrow.counterclockwise", color: .orange,
                            text: "Você pode revogar qualquer acesso ou apagar sua conta a qualquer momento.")
                        bulletPoint(icon: "exclamationmark.triangle.fill", color: .red,
                            text: "O app não substitui atendimento médico. Em crise, ligue \(CrisisNumbers.forCurrentLocale.crisisNumber) (\(CrisisNumbers.forCurrentLocale.crisisName)).")
                    }
                    .padding(14)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

                    // ── Accept button ────────────────────────────────────────
                    Button(action: onAccept) {
                        Text("Li e aceito — Continuar")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canAccept)
                    .animation(.easeInOut(duration: 0.15), value: canAccept)

                    if !canAccept {
                        Text("Marque as duas caixas acima para continuar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .sheet(item: $activeDocument) { document in
            LegalDocumentView(title: document.title, documentText: document.text)
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: Private helpers

    @ViewBuilder
    private func consentRow(
        isChecked: Binding<Bool>,
        label: String,
        linkLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                isChecked.wrappedValue.toggle()
            } label: {
                Image(systemName: isChecked.wrappedValue
                      ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isChecked.wrappedValue ? Color.neuroOrange : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isChecked.wrappedValue ? "Desmarcado" : "Marcado")

            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                Button(action: action) {
                    Text(linkLabel)
                        .font(.subheadline.weight(.semibold))
                        .underline()
                        .foregroundStyle(Color.neuroOrange)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func bulletPoint(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
    }
}
