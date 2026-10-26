//
//  BrandColors.swift
//  Neuremia
//
//  Brand color constants extracted from ContentView.swift (QC1).
//  Internal access so all files in the module can use them.
//

import SwiftUI
import UIKit

enum DataResidencyPolicy {
    static let localOnlyMode = true
    static var remoteSyncEnabled: Bool { !localOnlyMode }
}

extension Color {
    // Core brand identity
    static let neuroYellow = Color(red: 1.0, green: 0.78, blue: 0.0)    // #FFC800
    static let neuroGold = Color(red: 1.0, green: 0.72, blue: 0.0)      // #FFB800
    static let neuroNavy = Color(red: 0.03, green: 0.12, blue: 0.29)    // #071E49
    static let neuroNavySoft = Color(red: 0.05, green: 0.17, blue: 0.36)
    static let neuroNavyGlass = Color(red: 0.10, green: 0.22, blue: 0.38)
    static let neuroCardNavy = Color(red: 0.04, green: 0.13, blue: 0.30)

    // Interaction tokens
    static let neuroCTA = Color.neuroYellow
    static let neuroCTAPressed = Color.neuroGold
    static let neuroCTASelected = Color.neuroYellow
    static let neuroCTADisabled = Color.neuroYellow.opacity(0.42)
    static let neuroInteractiveHighlight = Color.neuroYellow
    static let neuroProgress = Color.neuroYellow
    static let neuroMission = Color.neuroYellow
    static let neuroScoreHighlight = Color.neuroYellow
    static let neuroCardOnDark = Color.neuroNavySoft
    static let neuroTextOnYellow = Color.neuroNavy
    static let neuroTextOnNavy = Color.white

    // Legacy accent retained for older code paths; new CTA/progress surfaces should use yellow tokens above.
    static let neuroOrange = Color.neuroYellow
}

extension UIColor {
    // Contraparte UIKit para uso em PDF/CoreGraphics onde SwiftUI.Color
    // não pode ser resolvida (BackupView.swift usa em context.cgContext.fill).
    static let neuroYellow = UIColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1)
    static let neuroGold = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1)
    static let neuroNavy = UIColor(red: 0.03, green: 0.12, blue: 0.29, alpha: 1)
    static let neuroNavySoft = UIColor(red: 0.05, green: 0.17, blue: 0.36, alpha: 1)
    static let neuroNavyGlass = UIColor(red: 0.10, green: 0.22, blue: 0.38, alpha: 1)
    static let neuroCardNavy = UIColor(red: 0.04, green: 0.13, blue: 0.30, alpha: 1)
    static let neuroCTA = UIColor.neuroYellow
    static let neuroProgress = UIColor.neuroYellow
    static let neuroMission = UIColor.neuroYellow
    static let neuroOrange = UIColor.neuroYellow
}

struct NeuroCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NeuroCTAButtonStyle {
    static var neuroCTA: NeuroCTAButtonStyle { NeuroCTAButtonStyle() }
}
