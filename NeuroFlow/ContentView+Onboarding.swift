//
//  ContentView+Onboarding.swift
//  NeuroFlow
//

import SwiftUI
import SwiftData

extension ContentView {
    // MARK: - Onboarding (Sprint 20)

    /// Apresenta o onboarding apenas para pacientes (não para clínicos) e só
    /// enquanto a flag persistida não estiver marcada. Liga em escrita só
    /// para o getter de `isPresented`; o `set` é no-op porque o flow controla
    /// fechamento via mudança do `@AppStorage`.
    var shouldShowOnboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding && activeRole == .patient },
            set: { _ in }
        )
    }

    @ViewBuilder
    var onboardingFlow: some View {
        TabView(selection: $onboardingStep) {
            onboardingSlide(
                step: 0,
                icon: "heart.text.square.fill",
                tint: .red,
                title: "Bem-vindo ao NeuroFlow",
                body: "Acompanhe seu humor todos os dias com calma. O app guarda seus registros com segurança no seu aparelho e na sua conta.",
                ctaText: "Vamos lá"
            ) {
                onboardingStep = 1
            }

            onboardingSlide(
                step: 1,
                icon: "lock.shield.fill",
                tint: .green,
                title: "Você decide quem vê",
                body: "Profissionais só acompanham seus dados se você aceitar o convite. Você pode cancelar o acesso a qualquer momento.",
                ctaText: "Continuar"
            ) {
                onboardingStep = 2
            }

            onboardingCareFocus
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(appBackground.ignoresSafeArea())
    }

    @ViewBuilder
    func onboardingSlide(
        step: Int,
        icon: String,
        tint: Color,
        title: String,
        body: String,
        ctaText: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 96))
                .foregroundStyle(tint)
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: action) {
                Text(ctaText)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .tag(step)
    }

    var onboardingCareFocus: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 72))
                .foregroundStyle(Color.neuroOrange)
            Text("Qual é o seu foco de cuidado?")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Isso ajusta as perguntas que o app faz e o que ele observa. Você pode mudar depois em Configurações.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(CareFocus.allCases) { focus in
                        Button {
                            selectedCareFocus = focus
                        } label: {
                            HStack {
                                Text(focus.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if selectedCareFocus == focus {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.neuroOrange)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        selectedCareFocus == focus ? Color.neuroOrange : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }

            // Primário: completa o onboarding e usa o app sem conta.
            // O paciente pode criar/entrar na conta depois em Configurações.
            Button {
                let patient = ensurePatient()
                patient.consentAccepted = true
                do {
                    try modelContext.save()
                } catch {
                    saveStatusMessage = "Não foi possível salvar o consentimento: \(error.localizedDescription)"
                }
                hasCompletedOnboarding = true
                onboardingStep = 0
            } label: {
                Text("Começar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)

            // Secundário: tem conta ou quer criar antes de começar.
            // Completa o onboarding E abre o formulário de login diretamente,
            // sem exigir que o usuário descubra o caminho em Configurações.
            Button {
                let patient = ensurePatient()
                patient.consentAccepted = true
                do {
                    try modelContext.save()
                } catch {
                    saveStatusMessage = "Não foi possível salvar o consentimento: \(error.localizedDescription)"
                }
                hasCompletedOnboarding = true
                onboardingStep = 0
                // Abre a sheet de login após o onboarding fechar.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    isShowingLoginSheet = true
                }
            } label: {
                Text("Já tenho conta — entrar")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)

            Button("Continuar sem conta") {
                hasCompletedOnboarding = true
                onboardingStep = 0
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)
        }
    }


}
