//
//  GamificationComponents.swift
//  Neuremia
//
//  Componentes de UI para gamificação inspirada em gamificação
//

import SwiftUI

// MARK: - Constantes de Animação

struct GamificationAnimations {
    static let spring = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let quick = Animation.spring(response: 0.2, dampingFraction: 0.8)
    static let celebration = Animation.spring(response: 0.5, dampingFraction: 0.6)
    static let levelUp = Animation.spring(response: 0.6, dampingFraction: 0.5)
    static let bounce = Animation.spring(response: 0.4, dampingFraction: 0.6)
}

// MARK: - GamificationHeader

struct GamificationHeader: View {
    let currentXP: Int
    let currentLevel: LevelThreshold
    let nextLevel: LevelThreshold?
    let progress: Double
    let onXPGain: ((Int) -> Void)?

    @State private var displayedXP: Int = 0
    @State private var xpAnimation: Bool = false

    init(
        currentXP: Int,
        currentLevel: LevelThreshold,
        nextLevel: LevelThreshold?,
        progress: Double,
        onXPGain: ((Int) -> Void)? = nil
    ) {
        self.currentXP = currentXP
        self.currentLevel = currentLevel
        self.nextLevel = nextLevel
        self.progress = progress
        self.onXPGain = onXPGain
    }

    var body: some View {
        HStack(spacing: 16) {
            // Level Badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.neuroYellow, .neuroGold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                VStack(spacing: 0) {
                    Text("\(currentLevel.level)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.neuroTextOnYellow)
                }
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            }
            .scaleEffect(xpAnimation ? 1.15 : 1.0)
            .animation(GamificationAnimations.bounce, value: xpAnimation)

            // Level Info
            VStack(alignment: .leading, spacing: 4) {
                Text(currentLevel.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.neuroTextOnYellow)

                Text(currentLevel.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // XP Progress
                if let next = nextLevel {
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: progress)
                            .tint(.neuroYellow)
                            .background(Color.gray.opacity(0.2))

                        HStack {
                            Text("\(currentXP) XP")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.neuroProgress)

                            Spacer()

                            Text("\(next.xpRequired) XP")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    // Max level reached
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(Color.neuroGold)
                        Text("Nível Máximo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.neuroGold)
                    }
                }
            }

            Spacer()

            // XP Counter
            VStack(spacing: 2) {
                Text("\(displayedXP)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.neuroProgress)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: displayedXP)

                Text("XP Total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .onAppear {
            displayedXP = currentXP
        }
        .onChange(of: currentXP) { _, newValue in
            withAnimation(GamificationAnimations.quick) {
                displayedXP = newValue
                xpAnimation = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                xpAnimation = false
            }
        }
    }
}

// MARK: - DailyMissionsCarousel

struct DailyMissionsCarousel: View {
    let missions: [DailyMission]
    let isMissionComplete: (DailyMission) -> Bool
    let onMissionTap: (DailyMission) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Missões do Dia", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(Color.neuroMission)

                Spacer()

                Text("\(completedCount)/\(missions.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(missions) { mission in
                        MissionCard(
                            mission: mission,
                            isComplete: isMissionComplete(mission),
                            onTap: { onMissionTap(mission) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var completedCount: Int {
        missions.filter { isMissionComplete($0) }.count
    }
}

struct MissionCard: View {
    let mission: DailyMission
    let isComplete: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            if !isComplete {
                onTap()
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: mission.icon)
                        .font(.title2)
                        .foregroundStyle(isComplete ? .green : .neuroTextOnYellow)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isComplete ? Color.green.opacity(0.15) : Color.neuroTextOnYellow.opacity(0.12))
                        )

                    Spacer()

                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }

                Text(mission.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isComplete ? Color.primary : Color.neuroTextOnYellow)
                    .lineLimit(1)

                Text("+\(mission.xpReward) XP")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.neuroTextOnYellow)
            }
            .padding(14)
            .frame(width: 140)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isComplete ? Color.green.opacity(0.08) : Color.neuroMission)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isComplete ? Color.green.opacity(0.3) : Color.neuroCTAPressed.opacity(0.55), lineWidth: 2)
            }
        }
        .buttonStyle(.neuroCTA)
    }
}

// MARK: - StreakCalendar

struct StreakCalendar: View {
    let currentStreak: Int
    let longestStreak: Int
    let checkInDates: [Date]

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Sequência", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(Color.neuroProgress)

                Spacer()

                if currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(Color.neuroProgress)
                        Text("\(currentStreak) dias")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.neuroProgress)
                    }
                }
            }

            // Week view
            HStack(spacing: 8) {
                ForEach(weekDays, id: \.date) { dayInfo in
                    DayIndicator(
                        dayInfo: dayInfo,
                        hasCheckIn: hasCheckIn(on: dayInfo.date)
                    )
                }
            }

            // Longest streak info
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(Color.neuroGold)

                Text("Recorde: \(longestStreak) dias")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var weekDays: [DayInfo] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7

        return (0..<7).compactMap { offset in
            let dayOffset = offset - daysFromMonday
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                return nil
            }
            let dayName = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return DayInfo(date: date, dayName: dayName)
        }
    }

    private func hasCheckIn(on date: Date) -> Bool {
        checkInDates.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    struct DayInfo {
        let date: Date
        let dayName: String
    }
}

struct DayIndicator: View {
    let dayInfo: StreakCalendar.DayInfo
    let hasCheckIn: Bool

    @State private var isToday: Bool = false
    @State private var isAnimating: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(dayInfo.dayName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)

                if hasCheckIn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.neuroTextOnYellow)
                }

                if isToday && !hasCheckIn {
                    Circle()
                        .stroke(Color.neuroProgress, lineWidth: 2)
                        .frame(width: 36, height: 36)
                }

                if isToday && hasCheckIn {
                    // Fire animation for today
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.neuroProgress)
                        .offset(y: -2)
                }
            }
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .animation(
                hasCheckIn ? GamificationAnimations.celebration : .default,
                value: isAnimating
            )
        }
        .onAppear {
            let today = Calendar.current.startOfDay(for: Date())
            isToday = Calendar.current.isDate(dayInfo.date, inSameDayAs: today)
            if hasCheckIn && isToday {
                isAnimating = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isAnimating = false
                }
            }
        }
    }

    private var backgroundColor: Color {
        if hasCheckIn {
            return .neuroProgress
        } else if isToday {
            return .neuroProgress.opacity(0.2)
        } else {
            return .gray.opacity(0.1)
        }
    }
}

// MARK: - StreakRecoveryBanner

struct StreakRecoveryBanner: View {
    let previousStreak: Int
    let onCheckInTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title)
                    .foregroundStyle(Color.neuroProgress)
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.neuroProgress.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Que bom ter você de volta!")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(recoveryMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button(action: onCheckInTap) {
                Label("Fazer check-in", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.neuroYellow)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.neuroProgress.opacity(0.16), Color(.secondarySystemGroupedBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.neuroProgress.opacity(0.3), lineWidth: 1)
        }
    }

    private var recoveryMessage: String {
        if previousStreak >= 7 {
            return "Você estava em uma sequência incrível de \(previousStreak) dias. Que tal recomeçar?"
        } else if previousStreak >= 3 {
            return "Você estava em uma boa sequência. Cada dia é uma oportunidade!"
        } else {
            return "Cada dia é uma oportunidade de recomeçar. Bora continuar?"
        }
    }
}

// MARK: - BadgeGrid

struct BadgeGrid: View {
    let unlockedBadges: [Badge]
    let allBadgeDefinitions: [BadgeDefinition]
    let onBadgeTap: (BadgeDefinition) -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Conquistas", systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(Color.neuroGold)

                Spacer()

                Text("\(unlockedBadges.count)/\(allBadgeDefinitions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Recent unlocked badges
            if !recentUnlockedBadges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Desbloqueados recentemente")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recentUnlockedBadges, id: \.badgeId) { badge in
                                RecentBadgeView(badge: badge)
                            }
                        }
                    }
                }
            }

            // All badges grid
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(allBadgeDefinitions) { badgeDef in
                    BadgeCell(
                        definition: badgeDef,
                        isUnlocked: isUnlocked(badgeDef),
                        unlockedAt: unlockedDate(for: badgeDef),
                        onTap: { onBadgeTap(badgeDef) }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var recentUnlockedBadges: [Badge] {
        unlockedBadges
            .filter { $0.unlockedAt != nil }
            .sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    private func isUnlocked(_ definition: BadgeDefinition) -> Bool {
        unlockedBadges.contains { $0.badgeId == definition.id }
    }

    private func unlockedDate(for definition: BadgeDefinition) -> Date? {
        unlockedBadges.first { $0.badgeId == definition.id }?.unlockedAt
    }
}

struct RecentBadgeView: View {
    let badge: Badge

    @State private var isAnimating: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.neuroGold.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: badge.iconName)
                    .font(.title2)
                    .foregroundStyle(tierColor)
            }
            .scaleEffect(isAnimating ? 1.1 : 1.0)

            Text(badge.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .onAppear {
            isAnimating = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimating = false
            }
        }
    }

    private var tierColor: Color {
        switch badge.tier {
        case "Bronze": return Color(red: 0.8, green: 0.5, blue: 0.2)
        case "Prata": return Color(red: 0.75, green: 0.75, blue: 0.8)
        case "Ouro": return Color.neuroGold
        case "Platina": return Color(red: 0.9, green: 0.9, blue: 0.95)
        default: return .neuroProgress
        }
    }
}

struct BadgeCell: View {
    let definition: BadgeDefinition
    let isUnlocked: Bool
    let unlockedAt: Date?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? definition.tier.color.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: 44, height: 44)

                    if isUnlocked {
                        Image(systemName: definition.icon)
                            .font(.title3)
                            .foregroundStyle(definition.tier.color)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }

                Text(definition.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isUnlocked ? definition.tier.color.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WeeklyGoalProgressCard

struct WeeklyGoalProgressCard: View {
    let weeklyProgress: Int
    let weeklyGoal: Int
    let weekStartDate: Date
    let xpReward: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Meta Semanal", systemImage: "target")
                        .font(.headline)
                        .foregroundStyle(Color.neuroProgress)

                Spacer()

                Text("\(weeklyProgress)/\(weeklyGoal) dias")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(.neuroYellow)
                .background(Color.gray.opacity(0.2))

            HStack {
                if progress >= 1.0 {
                    Label("Meta atingida!", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    let remaining = weeklyGoal - weeklyProgress
                    Text("\(remaining) dia(s) restante(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if progress < 1.0 {
                    Text("+\(xpReward) XP ao completar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.neuroProgress)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var progress: Double {
        min(Double(weeklyProgress) / Double(weeklyGoal), 1.0)
    }
}

// MARK: - CelebrationOverlay

struct CelebrationOverlay: View {
    let celebration: CelebrationType
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false
    @State private var showConfetti: Bool = false

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
            if showConfetti {
                ConfettiView().ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(GamificationAnimations.celebration) {
                isVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }
        }
    }

    private var backgroundLayer: some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .onTapGesture { dismissWithAnimation() }
    }

    private var contentLayer: some View {
        VStack(spacing: 24) {
            iconLayer
            textLayer
            continueButton
        }
        .scaleEffect(isVisible ? 1.0 : 0.8)
    }

    private var iconLayer: some View {
        ZStack {
            Circle()
                .fill(gradient)
                .frame(width: 120, height: 120)
                .shadow(color: shadowColor.opacity(0.5), radius: 20, y: 10)

            Image(systemName: celebration.icon)
                .font(.system(size: 50))
                .foregroundStyle(.white)
                .scaleEffect(isVisible ? 1.0 : 0.3)
                .rotationEffect(.degrees(isVisible ? 0 : -20))
        }
    }

    private var textLayer: some View {
        VStack(spacing: 8) {
            Text(celebration.title)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 20)

            Text(celebration.subtitle)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 20)
        }
    }

    private var continueButton: some View {
        Button(action: dismissWithAnimation) {
            Text("Continuar")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.neuroTextOnYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 32)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
    }

    /// Cor sólida representativa do gradient — usada para o shadow, que só
    /// aceita `Color` (não `ShapeStyle`).
    private var shadowColor: Color {
        switch celebration {
        case .checkInComplete: return .green
        case .missionComplete: return .neuroMission
        case .badgeUnlock: return .neuroGold
        case .levelUp: return .neuroProgress
        case .streakMilestone: return .neuroProgress
        case .weeklyGoalComplete: return .green
        }
    }

    private var gradient: LinearGradient {
        switch celebration {
        case .checkInComplete:
            return LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .missionComplete:
            return LinearGradient(colors: [.neuroMission, .neuroCTAPressed], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .badgeUnlock:
            return LinearGradient(colors: [.neuroCTAPressed, .neuroMission], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .levelUp:
            return LinearGradient(colors: [.neuroMission, .neuroNavySoft], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .streakMilestone:
            return LinearGradient(colors: [.neuroProgress, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .weeklyGoalComplete:
            return LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func dismissWithAnimation() {
        withAnimation(GamificationAnimations.quick) {
            isVisible = false
            showConfetti = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - LevelUpCelebration
// Overlay dedicado para level-up (Sprint 26). Substitui o CelebrationOverlay
// genérico quando o tipo é `.levelUp` — três rings expandindo + medalhão
// gigante com o número do nível. Mais impactante que o overlay comum.

struct LevelUpCelebration: View {
    let newLevel: LevelThreshold
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var ringScale: CGFloat = 0.3

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 32) {
                levelMedallion
                titleBlock
                continueButton
            }
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isVisible = true
                ringScale = 1.0
            }
            HapticManager.shared.levelUp()
        }
    }

    private var levelMedallion: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.neuroProgress, Color.neuroCTAPressed],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ).opacity(0.3),
                        lineWidth: 2
                    )
                    .frame(width: 140 + CGFloat(index * 20), height: 140 + CGFloat(index * 20))
                    .scaleEffect(isVisible ? 1.0 : 0.5)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(Double(index) * 0.15), value: isVisible)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.neuroCTA, Color.neuroCTAPressed, Color.neuroCTA],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: Color.neuroProgress.opacity(0.42), radius: 20, y: 10)
                .scaleEffect(ringScale)

            VStack(spacing: 0) {
                Text("NÍVEL")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.neuroTextOnYellow.opacity(0.84))

                Text("\(newLevel.level)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Color.neuroTextOnYellow)
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("Parabéns!")
                .font(.title.weight(.bold))
                .foregroundStyle(Color.white)

            Text(newLevel.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.neuroYellow)

            Text(newLevel.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.8))
        }
    }

    private var continueButton: some View {
        Button(action: dismiss) {
            Text("Continuar")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.neuroTextOnYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 32)
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }
}

// MARK: - ConfettiView

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animationTimer: Timer?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(particle.opacity)
                }
            }
            .onAppear {
                animationTimer?.invalidate()
                createParticles(in: geometry.size)
                // Passa a altura do container ao invés de UIScreen.main
                // (deprecated no iOS 26.0). O confetti só precisa saber
                // quando uma partícula saiu da view atual.
                animateParticles(maxY: geometry.size.height)
            }
            .onDisappear {
                animationTimer?.invalidate()
                animationTimer = nil
            }
        }
    }

    private func createParticles(in size: CGSize) {
        let colors: [Color] = [.neuroYellow, .neuroGold, .neuroNavy, .green, .white]

        particles = (0..<50).map { _ in
            ConfettiParticle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: -20
                ),
                color: colors.randomElement()!,
                size: CGFloat.random(in: 6...12),
                opacity: 1.0
            )
        }
    }

    private func animateParticles(maxY: CGFloat) {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            withAnimation(.linear(duration: 0.1)) {
                for index in particles.indices {
                    particles[index].position.y += CGFloat.random(in: 4...12)
                    particles[index].position.x += CGFloat.random(in: -3...3)
                    particles[index].opacity -= 0.015
                }

                particles.removeAll { $0.opacity <= 0 || $0.position.y > maxY + 50 }
            }

            if particles.isEmpty {
                timer.invalidate()
                animationTimer = nil
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    var opacity: Double
}

// MARK: - LevelProgressCard

struct LevelProgressCard: View {
    let currentLevel: LevelThreshold
    let nextLevel: LevelThreshold?
    let progress: Double
    let recentXP: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.neuroYellow, .neuroGold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Text("\(currentLevel.level)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(Color.neuroTextOnYellow)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentLevel.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let next = nextLevel {
                        Text("Próximo: \(next.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("+\(recentXP)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.neuroProgress)
                    Text("XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let next = nextLevel {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(.neuroYellow)
                        .background(Color.gray.opacity(0.2))

                    HStack {
                        Text("\(progress * 100, specifier: "%.0f")% para \(next.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("Nível \(next.level)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.neuroProgress)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - XPBadge

struct XPBadge: View {
    let xp: Int
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: size * 0.5, weight: .bold))

            Text("+\(xp)")
                .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(Color.neuroTextOnYellow)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.neuroCTA, .neuroCTAPressed],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
    }
}
