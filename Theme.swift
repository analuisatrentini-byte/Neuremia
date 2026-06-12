//
//  Theme.swift
//  NeuroFlow
//
//  Brand palette and shared SwiftUI modifiers. Extracted from ContentView so
//  the design tokens live in one place and can be reused by future views.
//

import SwiftUI
import UIKit

extension Color {
    static let neuroYellow = Color(red: 1.0, green: 0.82, blue: 0.02)
    static let neuroGold = Color(red: 1.0, green: 0.66, blue: 0.0)
    static let neuroOrange = Color(red: 1.0, green: 0.48, blue: 0.0)
}

extension UIColor {
    static let neuroGold = UIColor(red: 1.0, green: 0.66, blue: 0.0, alpha: 1)
}

struct NeuroFlowPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    /// Shared card container used across NeuroFlow dashboards.
    func panelStyle() -> some View {
        modifier(NeuroFlowPanelStyle())
    }
}
