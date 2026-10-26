//
//  ContentView+Onboarding.swift
//  Neuremia
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
            get: {
                // Duas fullScreenCover ativas simultaneamente (legal +
                // onboarding) renderizam tela branca no primeiro launch.
                // Só apresenta o onboarding depois que o consent legal
                // já foi aceito — evita a colisão de covers.
                !needsLegalAcceptance
                    && !hasCompletedOnboarding
                    && activeRole == .patient
            },
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
                title: "Bem-vindo à Neuremia",
                body: "Acompanhe seu humor todos os dias com calma. Nesta versão, seus registros clínicos ficam protegidos no seu aparelho.",
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

            // Sprint 26: introduz a gamificação — streak, XP e conquistas —
            // antes do care focus, para o paciente entender que o esforço
            // diário é reconhecido. Tom acolhedor, não infantil.
            onboardingGamificationIntro
                .tag(2)

            onboardingCareFocus
                .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(appBackground.ignoresSafeArea())
    }

    /// Slide de introdução à gamificação. Três "pilares" em linha para
    /// deixar claro o que o paciente vai encontrar: constância (streak),
    /// esforço reconhecido (XP) e conquistas (badges). Tom acolhedor,
    /// nunca infantil — este é um app de saúde.
    var onboardingGamificationIntro: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.neuroYellow.opacity(0.35), Color.neuroOrange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                Image(systemName: "sparkles")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.neuroOrange)
                    .symbolEffect(.pulse, options: .repeating.speed(0.4))
            }

            VStack(spacing: 10) {
                Text("Seu esforço fica visível")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Pequenos passos diários viram progresso concreto. Sem pressão, no seu ritmo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                onboardingPillarRow(
                    icon: "flame.fill",
                    tint: .orange,
                    title: "Sequência de dias",
                    body: "Cada dia registrado alimenta seu streak. Se um dia faltar, tudo bem — recomeçar sempre conta."
                )
                onboardingPillarRow(
                    icon: "bolt.fill",
                    tint: Color.neuroOrange,
                    title: "XP e níveis",
                    body: "Check-ins, escalas e reflexões acumulam experiência. Você sobe de nível conforme se conhece melhor."
                )
                onboardingPillarRow(
                    icon: "medal.fill",
                    tint: .purple,
                    title: "Conquistas discretas",
                    body: "Marcos ao longo do caminho. Ficam guardados na aba Progresso — para lembrar de onde você veio."
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                onboardingStep = 3
            } label: {
                Text("Continuar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func onboardingPillarRow(
        icon: String,
        tint: Color,
        title: String,
        body: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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

            if DataResidencyPolicy.remoteSyncEnabled {
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
            }

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
