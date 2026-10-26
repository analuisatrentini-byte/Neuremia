//
//  GamifiedHomeHero.swift
//  Neuremia
//
//  Componentes de topo da aba "Hoje" inspirados em gamificação: barra persistente
//  com streak + XP + nível, carrossel enxuto de missões e cartão hero de
//  check-in rápido. Objetivo: transformar a aba Hoje em um "launch pad"
//  visual em vez de um formulário longo, reduzindo cliques e reforçando
//  progresso já na primeira dobra.
//

import SwiftUI

// MARK: - GamifiedTopStrip

/// Barra compacta persistente no topo da aba "Hoje". Traz três indicadores
/// de progresso lado a lado: streak (fogo), nível e XP. Estilo "top bar" do
/// gamificação — sempre visível, informação instantânea de status.
struct GamifiedTopStrip: View {
    let streak: Int
    let level: LevelThreshold
    let currentXP: Int
    let nextLevelXP: Int?
    let progress: Double

    @State private var flamePulse = false

    var body: some View {
        HStack(spacing: 10) {
            streakPill
            levelPill
            xpProgressPill
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }

    private var streakPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(streak >= 1 ? Color.neuroProgress : Color(.tertiaryLabel))
                .scaleEffect(flamePulse ? 1.15 : 1.0)
                .animation(
                    streak >= 3
                        ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                        : .default,
                    value: flamePulse
                )
            Text("\(streak)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(streak >= 1 ? Color.neuroTextOnNavy : Color(.tertiaryLabel))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.neuroCardOnDark.opacity(0.92)))
        .overlay {
            Capsule().stroke(
                streak >= 1 ? Color.neuroProgress.opacity(0.40) : Color.clear,
                lineWidth: 1
            )
        }
        .onAppear { if streak >= 3 { flamePulse = true } }
        .accessibilityLabel(
            streak > 0
                ? "Sequência de \(streak) dias"
                : "Nenhuma sequência ativa"
        )
    }

    private var levelPill: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.neuroCTA, .neuroCTAPressed],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                Text("\(level.level)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.neuroTextOnYellow)
            }
            Text(level.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(Color.neuroTextOnNavy)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.neuroCardOnDark.opacity(0.92)))
        .accessibilityLabel("Nível \(level.level), \(level.title)")
    }

    private var xpProgressPill: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.neuroProgress)
                Text("\(currentXP) XP")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.neuroTextOnNavy)
                Spacer(minLength: 0)
                if let next = nextLevelXP {
                    Text("\(next)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.neuroNavy.opacity(0.55))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.neuroProgress, .neuroCTAPressed],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * progress))
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.neuroCardOnDark.opacity(0.92)))
        .accessibilityLabel(
            nextLevelXP.map { "\(currentXP) de \($0) XP para o próximo nível" }
                ?? "\(currentXP) XP no nível máximo"
        )
    }
}

// MARK: - TodayMissionsRail

/// Versão compacta e horizontal das missões do dia — ocupa uma única linha
/// no topo do Home. `DailyMissionsCarousel` (visual maior) continua na
/// aba Progresso para o detalhe.
struct TodayMissionsRail: View {
    let missions: [DailyMission]
    let isMissionComplete: (DailyMission) -> Bool
    let onMissionTap: (DailyMission) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Missões de hoje", systemImage: "target")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.neuroMission)
                Spacer()
                Text("\(completedCount)/\(missions.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(missions) { mission in
                        MissionRailChip(
                            mission: mission,
                            isComplete: isMissionComplete(mission),
                            onTap: { onMissionTap(mission) }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var completedCount: Int {
        missions.filter { isMissionComplete($0) }.count
    }
}

private struct MissionRailChip: View {
    let mission: DailyMission
    let isComplete: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            if !isComplete { onTap() }
        }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isComplete ? Color.green.opacity(0.15) : Color.neuroTextOnYellow.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: isComplete ? "checkmark" : mission.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isComplete ? .green : .neuroTextOnYellow)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(mission.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.neuroTextOnYellow)
                        .lineLimit(1)
                    Text("+\(mission.xpReward) XP")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isComplete ? Color.neuroTextOnYellow.opacity(0.72) : Color.neuroTextOnYellow)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isComplete ? Color.neuroMission.opacity(0.78) : Color.neuroMission)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isComplete ? Color.green.opacity(0.45) : Color.neuroCTAPressed.opacity(0.55), lineWidth: 1)
            }
            .opacity(isComplete ? 0.82 : 1.0)
        }
        .buttonStyle(.neuroCTA)
        .accessibilityLabel("Missão: \(mission.title). \(isComplete ? "Concluída" : "Pendente"). Recompensa: \(mission.xpReward) XP.")
    }
}

// MARK: - HeroCheckInCard

/// Cartão hero que abre a aba Hoje: mensagem de acolhimento + resumo do
/// estado atual + CTA prominente que rola até o formulário do diário.
/// Substitui o antigo `header` genérico por algo focado em ação.
struct HeroCheckInCard: View {
    let greeting: String
    let subtitle: String
    let hasCheckedInToday: Bool
    let onQuickCheckInTap: () -> Void

    @State private var iconBounce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: hasCheckedInToday
                                    ? [.green.opacity(0.85), .teal.opacity(0.7)]
                                    : [.neuroCTA, .neuroCTAPressed],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: hasCheckedInToday ? "checkmark.seal.fill" : "heart.text.square.fill")
                        .font(.title2)
                        .foregroundStyle(hasCheckedInToday ? Color.neuroTextOnNavy : Color.neuroTextOnYellow)
                        .symbolEffect(.bounce, value: iconBounce)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: onQuickCheckInTap) {
                HStack(spacing: 8) {
                    Image(systemName: hasCheckedInToday ? "pencil.and.list.clipboard" : "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                    Text(hasCheckedInToday ? "Ajustar registro de hoje" : "Fazer check-in agora")
                        .font(.subheadline.weight(.bold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .opacity(0.7)
                }
                .foregroundStyle(hasCheckedInToday ? Color.neuroTextOnNavy : Color.neuroTextOnYellow)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: hasCheckedInToday
                            ? [.green, .teal]
                            : [.neuroCTA, .neuroCTAPressed],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .shadow(
                    color: (hasCheckedInToday ? Color.green : Color.neuroCTA).opacity(0.25),
                    radius: 8, y: 4
                )
            }
            .buttonStyle(.neuroCTA)
            .accessibilityHint("Abre o formulário de check-in do diário.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.neuroCardOnDark.opacity(0.90))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.neuroScoreHighlight.opacity(0.22), lineWidth: 1)
        }
        .onAppear {
            // Bounce sutil ao aparecer para chamar atenção sem irritar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                iconBounce.toggle()
            }
        }
    }
}

// MARK: - QuickActionsRow

/// Linha horizontal com 3-4 atalhos discretos abaixo do hero: SOS, Escalas,
/// Aprender. Reduz cliques para as ações secundárias mais usadas sem
/// ocupar espaço na tab bar principal.
struct QuickActionsRow: View {
    let onCrisisTap: () -> Void
    let onScalesTap: () -> Void
    let onLearnTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            QuickAction(
                icon: "cross.case.fill",
                label: "Apoio",
                tint: .red,
                action: onCrisisTap
            )
            .accessibilityLabel("Apoio em crise")

            QuickAction(
                icon: "list.clipboard.fill",
                label: "Escalas",
                tint: .neuroCTA,
                action: onScalesTap
            )
            .accessibilityLabel("Check-up estruturado")

            QuickAction(
                icon: "graduationcap.fill",
                label: "Aprender",
                tint: .neuroCTA,
                action: onLearnTap
            )
            .accessibilityLabel("Psicoeducação")
        }
    }
}

private struct QuickAction: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.neuroTextOnYellow)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.neuroNavy.opacity(0.12))
                    )
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.neuroTextOnYellow)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.neuroCTA)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.neuroCTAPressed.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.neuroCTA)
    }
}

// MARK: - ProgressProfileHeader

/// Cabeçalho grande da aba "Progresso" — identidade de gamificação para a página:
/// nome do usuário, level ring com progresso XP e três stats de destaque
/// (streak atual, recorde, badges). Complementa a `GamifiedTopStrip` da
/// aba Hoje (que é compacta) — aqui o foco é dar uma sensação de perfil.
struct ProgressProfileHeader: View {
    let displayName: String
    let level: LevelThreshold
    let progress: Double
    let currentXP: Int
    let nextLevelXP: Int?
    let currentStreak: Int
    let longestStreak: Int
    let unlockedBadgesCount: Int

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                levelRing
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(level.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.neuroYellow)
                    Text(level.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            xpProgressRow

            statsRow
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.neuroYellow.opacity(0.18),
                            Color(.secondarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.neuroGold.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var levelRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemGroupedBackground), lineWidth: 6)
                .frame(width: 68, height: 68)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.neuroYellow, .neuroGold],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 68, height: 68)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: progress)
            Text("\(level.level)")
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("Nível \(level.level), \(Int(progress * 100)) por cento")
    }

    private var xpProgressRow: some View {
        VStack(spacing: 6) {
            HStack {
                Label("\(currentXP) XP", systemImage: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.neuroYellow)
                Spacer()
                if let next = nextLevelXP {
                    Text("\(next - currentXP) XP para o próximo nível")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nível máximo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.neuroGold)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemGroupedBackground))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.neuroYellow, .neuroGold],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * progress))
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: progress)
                }
            }
            .frame(height: 8)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            ProfileStatTile(
                icon: "flame.fill",
                tint: .neuroYellow,
                value: "\(currentStreak)",
                label: currentStreak == 1 ? "dia atual" : "dias atuais"
            )
            ProfileStatTile(
                icon: "trophy.fill",
                tint: .neuroGold,
                value: "\(longestStreak)",
                label: "recorde"
            )
            ProfileStatTile(
                icon: "medal.fill",
                tint: .neuroYellow,
                value: "\(unlockedBadgesCount)",
                label: "conquistas"
            )
        }
    }
}

private struct ProfileStatTile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - InsightsHeroCard

/// Hero da aba "Explorar" — resumo acolhedor da semana em vez de mergulhar
/// direto em gráficos. Mostra: título contextual, humor médio da semana,
/// contagem de registros e um insight leve. Alinha a aba com a linguagem
/// visual das outras (Hoje e Progresso) e reduz sensação de "planilha".
struct InsightsHeroCard: View {
    let weeklyCheckInCount: Int
    let weeklyAverageMood: Double?
    let weeklyMoodDelta: Double?
    let checkInStreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.neuroYellow, Color.neuroGold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Color.neuroTextOnYellow)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(insightTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(insightSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                InsightMetricTile(
                    icon: "calendar",
                    tint: .neuroYellow,
                    value: "\(weeklyCheckInCount)",
                    label: weeklyCheckInCount == 1 ? "registro" : "registros",
                    caption: "esta semana"
                )
                InsightMetricTile(
                    icon: "face.smiling",
                    tint: .green,
                    value: moodDisplay,
                    label: "humor médio",
                    caption: deltaCaption
                )
                InsightMetricTile(
                    icon: "flame.fill",
                    tint: .neuroYellow,
                    value: "\(checkInStreak)",
                    label: checkInStreak == 1 ? "dia" : "dias",
                    caption: "sequência"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .contain)
    }

    private var insightTitle: String {
        if weeklyCheckInCount == 0 {
            return "Sua jornada começa aqui"
        }
        if weeklyCheckInCount >= 5 {
            return "Semana consistente"
        }
        return "Como está sua semana"
    }

    private var insightSubtitle: String {
        if weeklyCheckInCount == 0 {
            return "Faça o primeiro check-in para começar a ver padrões."
        }
        if let delta = weeklyMoodDelta {
            if delta >= 0.5 {
                return "Seu humor subiu em relação à semana passada. Continue observando o que ajudou."
            }
            if delta <= -0.5 {
                return "Semana mais difícil que a anterior. O padrão está registrado — nada perdido."
            }
        }
        return "Um panorama das suas últimas semanas — sem julgamento."
    }

    private var moodDisplay: String {
        guard let mood = weeklyAverageMood, mood > 0 else { return "—" }
        return String(format: "%.1f", mood)
    }

    private var deltaCaption: String {
        guard let delta = weeklyMoodDelta else { return "sem comparação" }
        if delta > 0.1 {
            return "↑ vs. anterior"
        }
        if delta < -0.1 {
            return "↓ vs. anterior"
        }
        return "estável"
    }
}

private struct InsightMetricTile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String
    let caption: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label), \(caption)")
    }
}

// MARK: - EmptyStateHomeCard

/// Estado vazio acolhedor para a Home quando ainda não há check-ins.
/// Aparece abaixo do hero e dá contexto do que esperar do primeiro registro.
struct EmptyStateHomeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
                Text("Seu primeiro passo")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Text("O primeiro check-in demora menos de um minuto e libera:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                EmptyBenefit(icon: "flame.fill", tint: .neuroYellow, text: "Início do seu streak")
                EmptyBenefit(icon: "bolt.fill", tint: Color.neuroYellow, text: "+50 XP e a badge \"Primeiro passo\"")
                EmptyBenefit(icon: "chart.line.uptrend.xyaxis", tint: .neuroYellow, text: "Base para os primeiros padrões")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.green.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyBenefit: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - NextMilestoneCard

/// Cartão "próximo objetivo" — padrão de gamificação, que sempre
/// mostra ao usuário qual é a próxima meta alcançável e o quanto falta.
/// Combina três candidatos (próxima streak milestone, próximo nível, próxima
/// badge de streak/check-in) e escolhe o MAIS PRÓXIMO — para que o paciente
/// sempre veja algo atingível a curto prazo.
struct NextMilestoneCard: View {
    let currentStreak: Int
    let currentXP: Int
    let currentLevel: LevelThreshold
    let nextLevel: LevelThreshold?
    let checkInCount: Int

    var body: some View {
        let milestone = pickMilestone()

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.neuroYellow)
                Text("Próximo objetivo")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(milestone.tint.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: milestone.icon)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(milestone.tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(milestone.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(milestone.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemGroupedBackground))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [milestone.tint, milestone.tint.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * milestone.progress))
                            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: milestone.progress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(milestone.progressLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text("\(Int(milestone.progress * 100))%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(milestone.tint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Próximo objetivo: \(milestone.title). \(milestone.progressLabel).")
    }

    private struct Milestone {
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
        let progress: Double
        let progressLabel: String
    }

    /// Escolhe o candidato mais perto de ser completado (maior `progress`).
    /// Garante que o card sempre traga uma vitória plausível a curto prazo.
    private func pickMilestone() -> Milestone {
        var candidates: [Milestone] = []

        // Candidato 1: próximo marco de streak
        let streakMilestones = [3, 7, 14, 30, 100]
        if let nextStreak = streakMilestones.first(where: { $0 > currentStreak }) {
            let progress = min(Double(currentStreak) / Double(nextStreak), 1.0)
            candidates.append(Milestone(
                icon: "flame.fill",
                tint: .neuroYellow,
                title: "\(nextStreak) dias seguidos",
                subtitle: "Uma sequência que marca ritmo próprio.",
                progress: progress,
                progressLabel: "\(currentStreak) de \(nextStreak) dias"
            ))
        }

        // Candidato 2: próximo nível
        if let next = nextLevel {
            let xpInLevel = currentXP - currentLevel.xpRequired
            let xpNeeded = next.xpRequired - currentLevel.xpRequired
            let progress = xpNeeded > 0 ? min(Double(xpInLevel) / Double(xpNeeded), 1.0) : 1.0
            candidates.append(Milestone(
                icon: "bolt.fill",
                tint: Color.neuroYellow,
                title: "Nível \(next.level) — \(next.title)",
                subtitle: next.subtitle,
                progress: progress,
                progressLabel: "\(xpInLevel) de \(xpNeeded) XP"
            ))
        }

        // Candidato 3: próxima badge de check-in por contagem (10 / 50 / 100)
        let checkInMilestones = [10, 50, 100]
        if let nextCheckMilestone = checkInMilestones.first(where: { $0 > checkInCount }) {
            let progress = min(Double(checkInCount) / Double(nextCheckMilestone), 1.0)
            candidates.append(Milestone(
                icon: "medal.fill",
                tint: .neuroYellow,
                title: "\(nextCheckMilestone) check-ins",
                subtitle: "Marco desbloqueia uma nova conquista.",
                progress: progress,
                progressLabel: "\(checkInCount) de \(nextCheckMilestone)"
            ))
        }

        // Escolhe o candidato com maior progresso (mais perto de ser atingido).
        // Fallback conservador para quando não há candidato (nível máximo + sem streak).
        return candidates.max(by: { $0.progress < $1.progress })
            ?? Milestone(
                icon: "crown.fill",
                tint: Color.neuroGold,
                title: "Nível máximo alcançado",
                subtitle: "Continue registrando — sua constância é o marco.",
                progress: 1.0,
                progressLabel: "Missão cumprida"
            )
    }
}
