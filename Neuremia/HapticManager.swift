//
//  HapticManager.swift
//  Neuremia
//
//  Gerenciador centralizado de feedback háptico para microinterações
//

import UIKit

final class HapticManager {
    static let shared = HapticManager()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        prepareGenerators()
    }

    private func prepareGenerators() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    // MARK: - Impact Feedback

    func lightImpact() {
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }

    func mediumImpact() {
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
    }

    func heavyImpact() {
        heavyGenerator.impactOccurred()
        heavyGenerator.prepare()
    }

    func impact(intensity: CGFloat) {
        lightGenerator.impactOccurred(intensity: intensity)
        lightGenerator.prepare()
    }

    // MARK: - Selection Feedback

    func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    // MARK: - Notification Feedback

    func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }

    // MARK: - App-Specific Haptics

    func tabSelection() {
        selection()
    }

    func buttonTap() {
        lightImpact()
    }

    func checkbox() {
        lightImpact()
    }

    func toggle() {
        mediumImpact()
    }

    func saveSuccess() {
        success()
    }

    func levelUp() {
        // Custom pattern: heavy + success
        heavyImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.success()
        }
    }

    func streakFire() {
        // Rising intensity pattern for streak milestones
        lightImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.mediumImpact()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.heavyImpact()
        }
    }

    func badgeUnlock() {
        // Medal-like pattern
        mediumImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.lightImpact()
        }
    }

    func missionComplete() {
        mediumImpact()
    }

    func goalReached() {
        success()
    }

    func crisisAlert() {
        // Urgent pattern
        heavyImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.heavyImpact()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.warning()
        }
    }

    func pullToRefresh() {
        lightImpact()
    }

    func scrollReachedEnd() {
        lightImpact()
    }
}
