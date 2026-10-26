//
//  GamificationManager.swift
//  Neuremia
//
//  Gerencia XP, níveis, badges e missões diárias
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Configurações de XP

struct XPConfig {
    /// XP awarded for completing a daily check-in
    static let dailyCheckInXP = 50
    /// Bonus XP for first check-in of the day
    static let firstCheckInBonusXP = 100
    /// Bonus XP for filling optional detail fields
    static let detailedCheckInXP = 20
    /// Bonus XP for 7-day streak
    static let streak7DayBonusXP = 100
    /// Bonus XP for 14-day streak
    static let streak14DayBonusXP = 200
    /// Bonus XP for 30-day streak
    static let streak30DayBonusXP = 500
    /// XP for completing a daily mission
    static let missionCompleteXP = 30
    /// XP for completing a clinical scale
    static let scaleCompleteXP = 75
    /// XP for first scale completion
    static let firstScaleBonusXP = 150
}

// MARK: - Configurações de Nível

struct LevelThreshold: Identifiable, Equatable {
    let id = UUID()
    let level: Int
    let xpRequired: Int
    let title: String
    let subtitle: String

    static let allLevels: [LevelThreshold] = [
        LevelThreshold(level: 1, xpRequired: 0, title: "Iniciante", subtitle: "Primeiro passo dado"),
        LevelThreshold(level: 2, xpRequired: 100, title: "Explorador", subtitle: "Descobrindo o caminho"),
        LevelThreshold(level: 3, xpRequired: 300, title: "Descobridor", subtitle: "Conhecendo seus padrões"),
        LevelThreshold(level: 4, xpRequired: 600, title: "Acompanhante", subtitle: "Mantendo o ritmo"),
        LevelThreshold(level: 5, xpRequired: 1000, title: "Consistente", subtitle: "Uma rotina de cuidado"),
        LevelThreshold(level: 6, xpRequired: 1500, title: "Observador", subtitle: "Percependo mudanças"),
        LevelThreshold(level: 7, xpRequired: 2200, title: "Resiliente", subtitle: "Superando desafios"),
        LevelThreshold(level: 8, xpRequired: 3000, title: "Fortalecedor", subtitle: "Construindo força interior"),
        LevelThreshold(level: 9, xpRequired: 4000, title: "Protetor", subtitle: "Cuidador de si mesmo"),
        LevelThreshold(level: 10, xpRequired: 5500, title: "Guardião", subtitle: "Guardião do Bem-estar"),
    ]

    static func level(for xp: Int) -> LevelThreshold {
        var current = allLevels[0]
        for level in allLevels {
            if xp >= level.xpRequired {
                current = level
            } else {
                break
            }
        }
        return current
    }

    static func nextLevel(after level: Int) -> LevelThreshold? {
        allLevels.first { $0.level == level + 1 }
    }

    static func xpToNextLevel(currentXP: Int) -> Int {
        let currentLevel = level(for: currentXP)
        if let next = nextLevel(after: currentLevel.level) {
            return next.xpRequired - currentXP
        }
        return 0
    }

    static func progressToNextLevel(currentXP: Int) -> Double {
        let currentLevel = level(for: currentXP)
        guard let next = nextLevel(after: currentLevel.level) else { return 1.0 }

        let xpInCurrentLevel = currentXP - currentLevel.xpRequired
        let xpNeededForNextLevel = next.xpRequired - currentLevel.xpRequired

        return min(Double(xpInCurrentLevel) / Double(xpNeededForNextLevel), 1.0)
    }
}

// MARK: - Categorias de Badge

enum BadgeCategory: String, CaseIterable {
    case streak = "Sequência"
    case checkIn = "Check-in"
    case scale = "Escalas"
    case insight = "Insight"
    case consistency = "Constância"
    case milestone = "Marco"

    var icon: String {
        switch self {
        case .streak: return "flame.fill"
        case .checkIn: return "checkmark.circle.fill"
        case .scale: return "list.clipboard.fill"
        case .insight: return "lightbulb.fill"
        case .consistency: return "calendar"
        case .milestone: return "star.fill"
        }
    }
}

enum BadgeTier: String, CaseIterable {
    case bronze = "Bronze"
    case silver = "Prata"
    case gold = "Ouro"
    case platinum = "Platina"

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.8, green: 0.5, blue: 0.2)
        case .silver: return Color(red: 0.75, green: 0.75, blue: 0.8)
        case .gold: return Color.neuroGold
        case .platinum: return Color(red: 0.9, green: 0.9, blue: 0.95)
        }
    }
}

// MARK: - Definições de Badge

struct BadgeDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let category: BadgeCategory
    let tier: BadgeTier
    let xpReward: Int
    let requirement: String

    static let allBadges: [BadgeDefinition] = [
        // Streak Badges
        BadgeDefinition(id: "streak_3", name: "Três Dias", description: "Três dias consecutivos de check-in", icon: "flame.fill", category: .streak, tier: .bronze, xpReward: 25, requirement: "3 dias seguidos"),
        BadgeDefinition(id: "streak_7", name: "Uma Semana", description: "Sete dias consecutivos de check-in", icon: "flame.fill", category: .streak, tier: .silver, xpReward: 75, requirement: "7 dias seguidos"),
        BadgeDefinition(id: "streak_14", name: "Quatorze Dias", description: "Quatorze dias consecutivos de check-in", icon: "flame.fill", category: .streak, tier: .gold, xpReward: 150, requirement: "14 dias seguidos"),
        BadgeDefinition(id: "streak_30", name: "Mês de Cuidado", description: "Trinta dias consecutivos de check-in", icon: "flame.fill", category: .streak, tier: .platinum, xpReward: 300, requirement: "30 dias seguidos"),
        BadgeDefinition(id: "streak_100", name: "Cem Dias", description: "Cem dias de resiliência", icon: "flame.fill", category: .streak, tier: .platinum, xpReward: 500, requirement: "100 dias seguidos"),

        // Check-in Badges
        BadgeDefinition(id: "first_checkin", name: "Primeiro Passo", description: "Seu primeiro registro no app", icon: "figure.walk", category: .checkIn, tier: .bronze, xpReward: 50, requirement: "Primeiro check-in"),
        BadgeDefinition(id: "checkin_10", name: "Dez Registros", description: "Dez check-ins realizados", icon: "10.circle.fill", category: .checkIn, tier: .bronze, xpReward: 50, requirement: "10 check-ins"),
        BadgeDefinition(id: "checkin_50", name: "Meia Centena", description: "Cinquenta check-ins realizados", icon: "50.circle.fill", category: .checkIn, tier: .silver, xpReward: 100, requirement: "50 check-ins"),
        BadgeDefinition(id: "checkin_100", name: "Cem Registros", description: "Cem check-ins realizados", icon: "100.circle.fill", category: .checkIn, tier: .gold, xpReward: 200, requirement: "100 check-ins"),

        // Scale Badges
        BadgeDefinition(id: "scale_phq9", name: "PHQ-9", description: "Primeira autoavaliação PHQ-9", icon: "list.clipboard.fill", category: .scale, tier: .bronze, xpReward: 75, requirement: "Complete PHQ-9"),
        BadgeDefinition(id: "scale_gad7", name: "GAD-7", description: "Primeira autoavaliação GAD-7", icon: "list.clipboard.fill", category: .scale, tier: .bronze, xpReward: 75, requirement: "Complete GAD-7"),
        BadgeDefinition(id: "scale_ymrs", name: "YMRS", description: "Primeira autoavaliação YMRS", icon: "list.clipboard.fill", category: .scale, tier: .bronze, xpReward: 75, requirement: "Complete YMRS"),
        BadgeDefinition(id: "scales_all", name: "Tríade", description: "Completou PHQ-9, GAD-7 e YMRS", icon: "checkmark.seal.fill", category: .scale, tier: .gold, xpReward: 200, requirement: "Todas as escalas"),
        BadgeDefinition(id: "scales_5", name: "Avaliador", description: "Cinco escalas completadas", icon: "list.bullet.clipboard.fill", category: .scale, tier: .silver, xpReward: 100, requirement: "5 escalas"),

        // Journal Badges
        BadgeDefinition(id: "journal_first", name: "Reflexão", description: "Primeira entrada no diário", icon: "pencil.line", category: .insight, tier: .bronze, xpReward: 25, requirement: "Primeiro journal"),
        BadgeDefinition(id: "journal_7", name: "Reflexivo", description: "Sete entradas no diário", icon: "book.fill", category: .insight, tier: .silver, xpReward: 75, requirement: "7 journals"),
        BadgeDefinition(id: "journal_30", name: "Narrador", description: "Trinta entradas no diário", icon: "text.book.closed.fill", category: .insight, tier: .gold, xpReward: 150, requirement: "30 journals"),

        // Consistency Badges
        BadgeDefinition(id: "morning_7", name: "Madrugador", description: "Check-in pela manhã por 7 dias", icon: "sunrise.fill", category: .consistency, tier: .silver, xpReward: 75, requirement: "7 check-ins de manhã"),
        BadgeDefinition(id: "week_complete", name: "Semana Completa", description: "Check-in todos os dias de uma semana", icon: "calendar.badge.checkmark", category: .consistency, tier: .silver, xpReward: 100, requirement: "7 dias na semana"),
        BadgeDefinition(id: "medication_week", name: "Adesão Semanal", description: "Medicação tomada por 7 dias", icon: "pills.fill", category: .consistency, tier: .silver, xpReward: 75, requirement: "7 dias de medicação"),

        // Milestone Badges
        BadgeDefinition(id: "level_5", name: "Consistente", description: "Alcançou nível 5", icon: "star.fill", category: .milestone, tier: .silver, xpReward: 100, requirement: "Nível 5"),
        BadgeDefinition(id: "level_10", name: "Guardião", description: "Alcançou nível máximo", icon: "crown.fill", category: .milestone, tier: .platinum, xpReward: 500, requirement: "Nível 10"),
    ]

    static func badge(for id: String) -> BadgeDefinition? {
        allBadges.first { $0.id == id }
    }

    static func badges(for category: BadgeCategory) -> [BadgeDefinition] {
        allBadges.filter { $0.category == category }
    }
}

// MARK: - Missões Diárias

struct DailyMission: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let xpReward: Int
    let category: MissionCategory

    enum MissionCategory: String {
        case checkIn = "Check-in"
        case journal = "Reflexão"
        case medication = "Medicação"
        case scale = "Escala"
        case trigger = "Gatilhos"
        case sleep = "Sono"
    }

    static let alwaysMission = DailyMission(
        id: "daily_checkin",
        title: "Check-in do dia",
        description: "Registre como você está hoje",
        icon: "checkmark.circle.fill",
        xpReward: XPConfig.dailyCheckInXP,
        category: .checkIn
    )

    static func rotatingMissions(for date: Date) -> [DailyMission] {
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: date)

        var missions: [DailyMission] = []

        // Always include check-in mission
        missions.append(alwaysMission)

        // Rotate based on day of week
        switch dayOfWeek {
        case 1, 3, 5: // Sunday, Tuesday, Thursday
            missions.append(DailyMission(
                id: "journal_mission",
                title: "Reflexão do dia",
                description: "Escreva sobre seu dia no diário",
                icon: "pencil.line",
                xpReward: XPConfig.missionCompleteXP,
                category: .journal
            ))
        case 2, 4, 6: // Monday, Wednesday, Friday
            missions.append(DailyMission(
                id: "sleep_mission",
                title: "Registro de sono",
                description: "Quanto tempo você dormiu?",
                icon: "moon.zzz.fill",
                xpReward: XPConfig.missionCompleteXP,
                category: .sleep
            ))
        default: // Saturday
            missions.append(DailyMission(
                id: "scale_mission",
                title: "Check-up do bem-estar",
                description: "Complete uma escala clínica",
                icon: "list.clipboard.fill",
                xpReward: XPConfig.missionCompleteXP,
                category: .scale
            ))
        }

        // Add trigger awareness on some days
        if dayOfWeek == 3 || dayOfWeek == 6 { // Tuesday, Friday
            missions.append(DailyMission(
                id: "trigger_mission",
                title: "Consciência de gatilhos",
                description: "Identifique pelo menos um gatilho",
                icon: "exclamationmark.triangle.fill",
                xpReward: XPConfig.missionCompleteXP,
                category: .trigger
            ))
        }

        return missions
    }
}

// MARK: - Tipo de Celebração

enum CelebrationType {
    case checkInComplete
    case missionComplete(mission: DailyMission)
    case badgeUnlock(badge: BadgeDefinition)
    case levelUp(newLevel: LevelThreshold)
    case streakMilestone(days: Int)
    case weeklyGoalComplete

    var title: String {
        switch self {
        case .checkInComplete:
            return "Check-in Salvo!"
        case .missionComplete:
            return "Missão Completa!"
        case .badgeUnlock:
            return "Badge Desbloqueado!"
        case .levelUp(let level):
            return "Nível \(level.level)!"
        case .streakMilestone(let days):
            return "\(days) Dias!"
        case .weeklyGoalComplete:
            return "Meta Semanal!"
        }
    }

    var subtitle: String {
        switch self {
        case .checkInComplete:
            return "Seu registro foi salvo com sucesso"
        case .missionComplete(let mission):
            return "+\(mission.xpReward) XP"
        case .badgeUnlock(let badge):
            return "\(badge.name) - +\(badge.xpReward) XP"
        case .levelUp(let level):
            return "\(level.title)"
        case .streakMilestone(let days):
            return "Incrível, \(days) dias seguidos!"
        case .weeklyGoalComplete:
            return "Você atingiu sua meta semanal"
        }
    }

    var icon: String {
        switch self {
        case .checkInComplete: return "checkmark.circle.fill"
        case .missionComplete: return "star.fill"
        case .badgeUnlock: return "trophy.fill"
        case .levelUp: return "arrow.up.circle.fill"
        case .streakMilestone: return "flame.fill"
        case .weeklyGoalComplete: return "calendar.badge.checkmark"
        }
    }
}

// MARK: - GamificationManager

@Observable
final class GamificationManager {
    private(set) var profile: GamificationProfile?
    private(set) var todayMissions: [DailyMission] = []
    private(set) var recentCelebrations: [CelebrationType] = []
    private(set) var pendingCelebration: CelebrationType?
    private(set) var persistenceErrorMessage = ""

    private var modelContext: ModelContext?
    private var checkIns: [DailyCheckIn] = []
    private var assessments: [ScaleAssessment] = []
    private var missionLogs: [DailyMissionLog] = []

    // MARK: - Setup

    func configure(
        modelContext: ModelContext,
        patient: PatientProfile?,
        checkIns: [DailyCheckIn],
        assessments: [ScaleAssessment],
        missionLogs: [DailyMissionLog]
    ) {
        self.modelContext = modelContext
        self.checkIns = checkIns
        self.assessments = assessments
        self.missionLogs = missionLogs

        if let patient, let existingProfile = patient.gamificationProfile {
            self.profile = existingProfile
        } else if let patient {
            let newProfile = GamificationProfile()
            newProfile.patient = patient
            modelContext.insert(newProfile)
            patient.gamificationProfile = newProfile
            self.profile = newProfile
            save(modelContext, failureMessage: "Não foi possível inicializar seu progresso.")
        }

        generateTodayMissions()
    }

    func registerSavedCheckIn(_ checkIn: DailyCheckIn) {
        checkIns.removeAll { $0.dayKey == checkIn.dayKey }
        checkIns.append(checkIn)
    }

    func registerSavedAssessment(_ assessment: ScaleAssessment) {
        assessments.removeAll {
            $0.scaleName == assessment.scaleName &&
            Calendar.current.isDate($0.date, inSameDayAs: assessment.date)
        }
        assessments.append(assessment)
    }

    // MARK: - Computed Properties

    var totalXP: Int {
        profile?.totalXP ?? 0
    }

    var currentLevel: LevelThreshold {
        guard let profile else {
            return LevelThreshold.allLevels[0]
        }
        return LevelThreshold.level(for: profile.totalXP)
    }

    var nextLevel: LevelThreshold? {
        LevelThreshold.nextLevel(after: currentLevel.level)
    }

    var xpToNextLevel: Int {
        LevelThreshold.xpToNextLevel(currentXP: profile?.totalXP ?? 0)
    }

    var levelProgress: Double {
        LevelThreshold.progressToNextLevel(currentXP: profile?.totalXP ?? 0)
    }

    var currentStreak: Int {
        profile?.currentStreak ?? calculateCurrentStreak()
    }

    var longestStreak: Int {
        profile?.longestStreak ?? 0
    }

    var unlockedBadges: [Badge] {
        profile?.unlockedBadges ?? []
    }

    var recentBadges: [Badge] {
        unlockedBadges
            .filter { $0.unlockedAt != nil }
            .sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    // MARK: - XP Actions

    func awardXP(_ amount: Int, reason: String = "") {
        guard let profile else { return }

        let oldLevel = currentLevel
        profile.totalXP += amount
        let newLevel = currentLevel

        // Check for level up
        if newLevel.level > oldLevel.level {
            showCelebration(.levelUp(newLevel: newLevel))
        }

        save(modelContext, failureMessage: "Não foi possível salvar XP.")
    }

    func awardCheckInXP(isFirstOfDay: Bool, hasDetails: Bool, hasJournal: Bool) {
        var totalXP = XPConfig.dailyCheckInXP

        if isFirstOfDay {
            totalXP += XPConfig.firstCheckInBonusXP
        }

        if hasDetails {
            totalXP += XPConfig.detailedCheckInXP
        }

        awardXP(totalXP, reason: "Check-in")
        updateStreak()
        showCelebration(.checkInComplete)
    }

    func awardScaleXP(isFirstScale: Bool) {
        let xp = isFirstScale ? XPConfig.firstScaleBonusXP : XPConfig.scaleCompleteXP
        awardXP(xp, reason: "Escala")
    }

    func awardMissionXP(_ mission: DailyMission) {
        guard !isMissionComplete(mission) else { return }

        awardXP(mission.xpReward, reason: "Missão: \(mission.title)")
        showCelebration(.missionComplete(mission: mission))
        markMissionComplete(mission)
    }

    // MARK: - Streak

    private func updateStreak() {
        guard let profile else { return }

        let today = Calendar.current.startOfDay(for: Date())
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) else {
            return
        }

        if let lastDate = profile.lastCheckInDate {
            let lastDay = Calendar.current.startOfDay(for: lastDate)

            if Calendar.current.isDate(lastDay, inSameDayAs: today) {
                // Already checked in today, no streak change
                return
            } else if Calendar.current.isDate(lastDay, inSameDayAs: yesterday) {
                // Continuing streak
                profile.currentStreak += 1
            } else {
                // Streak broken, start fresh
                profile.currentStreak = 1
            }
        } else {
            // First check-in ever
            profile.currentStreak = 1
        }

        profile.lastCheckInDate = Date()

        // Update longest streak
        if profile.currentStreak > profile.longestStreak {
            profile.longestStreak = profile.currentStreak
        }

        // Check for streak milestones
        let milestones = [3, 7, 14, 30, 100]
        if milestones.contains(profile.currentStreak) {
            showCelebration(.streakMilestone(days: profile.currentStreak))
        }

        // Award streak bonuses
        if profile.currentStreak == 7 {
            awardXP(XPConfig.streak7DayBonusXP, reason: "Bônus 7 dias")
        } else if profile.currentStreak == 14 {
            awardXP(XPConfig.streak14DayBonusXP, reason: "Bônus 14 dias")
        } else if profile.currentStreak == 30 {
            awardXP(XPConfig.streak30DayBonusXP, reason: "Bônus 30 dias")
        }

        save(modelContext, failureMessage: "Não foi possível salvar sequência.")
    }

    private func calculateCurrentStreak() -> Int {
        let sortedCheckIns = checkIns.sorted { $0.date > $1.date }
        guard !sortedCheckIns.isEmpty else { return 0 }

        let calendar = Calendar.current
        var expected = calendar.startOfDay(for: Date())
        var streak = 0

        // Allow yesterday as start if no check-in today yet
        if let firstDate = sortedCheckIns.first?.date,
           calendar.isDateInYesterday(firstDate) {
            expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
        }

        for checkIn in sortedCheckIns {
            let day = calendar.startOfDay(for: checkIn.date)
            if calendar.isDate(day, inSameDayAs: expected) {
                streak += 1
                expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
            } else if day < expected {
                break
            }
        }

        return streak
    }

    // MARK: - Missions

    func generateTodayMissions() {
        todayMissions = DailyMission.rotatingMissions(for: Date())
    }

    func isMissionComplete(_ mission: DailyMission) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return missionLogs.contains { log in
            log.missionId == mission.id &&
            Calendar.current.isDate(log.date, inSameDayAs: today) &&
            log.isCompleted
        }
    }

    private func markMissionComplete(_ mission: DailyMission) {
        guard let context = modelContext else { return }

        let today = Calendar.current.startOfDay(for: Date())
        if missionLogs.contains(where: {
            $0.missionId == mission.id &&
            Calendar.current.isDate($0.date, inSameDayAs: today) &&
            $0.isCompleted
        }) {
            return
        }

        let log = DailyMissionLog(
            date: today,
            missionId: mission.id,
            isCompleted: true,
            xpEarned: mission.xpReward,
            completedAt: Date()
        )

        context.insert(log)
        missionLogs.append(log)
        save(context, failureMessage: "Não foi possível salvar missão.")
    }

    // MARK: - Badges

    func checkAndAwardBadges() {
        guard let context = modelContext, let profile else { return }

        let existingBadgeIds = Set(unlockedBadges.map { $0.badgeId })

        for badgeDef in BadgeDefinition.allBadges {
            if existingBadgeIds.contains(badgeDef.id) { continue }

            if shouldUnlock(badgeDef) {
                let badge = Badge(
                    badgeId: badgeDef.id,
                    name: badgeDef.name,
                    badgeDescription: badgeDef.description,
                    iconName: badgeDef.icon,
                    category: badgeDef.category.rawValue,
                    tier: badgeDef.tier.rawValue,
                    xpReward: badgeDef.xpReward,
                    requirement: badgeDef.requirement,
                    unlockedAt: Date()
                )

                context.insert(badge)
                profile.unlockedBadges.append(badge)
                awardXP(badgeDef.xpReward, reason: "Badge: \(badgeDef.name)")
                showCelebration(.badgeUnlock(badge: badgeDef))
            }
        }

        save(context, failureMessage: "Não foi possível salvar badge.")
    }

    func clearPersistenceError() {
        persistenceErrorMessage = ""
    }

    @discardableResult
    private func save(_ context: ModelContext?, failureMessage: String) -> Bool {
        guard let context else {
            persistenceErrorMessage = "\(failureMessage) Contexto de dados indisponível."
            return false
        }

        do {
            try context.save()
            return true
        } catch {
            persistenceErrorMessage = "\(failureMessage) \(error.localizedDescription)"
            return false
        }
    }

    private func shouldUnlock(_ badge: BadgeDefinition) -> Bool {
        let checkInCount = checkIns.count
        let journalCount = checkIns.filter { !$0.journalEntry.isEmpty }.count
        let scaleCount = assessments.count

        switch badge.id {
        case "first_checkin":
            return checkInCount >= 1
        case "checkin_10":
            return checkInCount >= 10
        case "checkin_50":
            return checkInCount >= 50
        case "checkin_100":
            return checkInCount >= 100
        case "streak_3":
            return currentStreak >= 3
        case "streak_7":
            return currentStreak >= 7
        case "streak_14":
            return currentStreak >= 14
        case "streak_30":
            return currentStreak >= 30
        case "streak_100":
            return currentStreak >= 100
        case "journal_first":
            return journalCount >= 1
        case "journal_7":
            return journalCount >= 7
        case "journal_30":
            return journalCount >= 30
        case "scale_phq9":
            return hasCompletedScale(.phq9)
        case "scale_gad7":
            return hasCompletedScale(.gad7)
        case "scale_ymrs":
            return hasCompletedScale(.ymrs)
        case "scales_all":
            return hasCompletedScale(.phq9)
                && hasCompletedScale(.gad7)
                && hasCompletedScale(.ymrs)
        case "scales_5":
            return scaleCount >= 5
        case "morning_7":
            return morningCheckInCount >= 7
        case "week_complete":
            return hasCompleteCalendarWeek
        case "medication_week":
            return consecutiveMedicationDays >= 7
        case "level_5":
            return currentLevel.level >= 5
        case "level_10":
            return currentLevel.level >= 10
        default:
            return false
        }
    }

    private func hasCompletedScale(_ scale: ScaleKind) -> Bool {
        assessments.contains { $0.scaleName == scale.rawValue }
    }

    private var morningCheckInCount: Int {
        checkIns.filter { checkIn in
            (5..<12).contains(Calendar.current.component(.hour, from: checkIn.date))
        }.count
    }

    private var hasCompleteCalendarWeek: Bool {
        let calendar = Calendar.current
        let groupedByWeek = Dictionary(grouping: checkIns) { checkIn in
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: checkIn.date)
            return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
        }
        return groupedByWeek.values.contains { weekEntries in
            Set(weekEntries.map { calendar.component(.weekday, from: $0.date) }).count >= 7
        }
    }

    private var consecutiveMedicationDays: Int {
        let calendar = Calendar.current
        let medicationDays = Set(checkIns.compactMap { checkIn -> Date? in
            guard checkIn.medicationTaken else { return nil }
            return calendar.startOfDay(for: checkIn.date)
        })
        guard !medicationDays.isEmpty else { return 0 }

        var longest = 0
        var current = 0
        var previousDay: Date?

        for day in medicationDays.sorted() {
            if let previousDay,
               calendar.dateComponents([.day], from: previousDay, to: day).day == 1 {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previousDay = day
        }
        return longest
    }

    // MARK: - Celebrations

    func showCelebration(_ type: CelebrationType) {
        pendingCelebration = type
        recentCelebrations.insert(type, at: 0)
        if recentCelebrations.count > 10 {
            recentCelebrations.removeLast()
        }
    }

    func dismissCelebration() {
        pendingCelebration = nil
    }

    // MARK: - Recovery Banner

    var shouldShowRecoveryBanner: Bool {
        guard let profile else { return false }
        guard let lastDate = profile.lastCheckInDate else { return false }

        let today = Calendar.current.startOfDay(for: Date())
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) else {
            return false
        }
        let lastDay = Calendar.current.startOfDay(for: lastDate)

        // Show if last check-in was yesterday and we haven't checked in today
        return Calendar.current.isDate(lastDay, inSameDayAs: yesterday) &&
               !Calendar.current.isDate(lastDay, inSameDayAs: today) &&
               profile.currentStreak > 0
    }

    var recoveryMessage: String {
        if profile?.currentStreak ?? 0 >= 7 {
            return "Que bom ter você de volta! Você estava em uma boa sequência."
        } else {
            return "Cada dia é uma oportunidade de recomeçar. Bora continuar?"
        }
    }
}
