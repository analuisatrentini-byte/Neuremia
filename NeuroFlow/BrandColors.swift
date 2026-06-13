//
//  BrandColors.swift
//  NeuroFlow
//
//  Brand color constants extracted from ContentView.swift (QC1).
//  Internal access so all files in the module can use them.
//

import SwiftUI
import UIKit

extension Color {
    // Sprint E #6: fonte da cor agora vive em Assets.xcassets/BrandYellow.colorset
    // com variantes light + dark. "BrandYellow" não colide com o símbolo
    // autogerado pelo Color Asset Symbols do iOS 17+ (Color.neuroYellow).
    static let neuroYellow = Color("BrandYellow")
    static let neuroGold = Color(red: 1.0, green: 0.66, blue: 0.0)
    static let neuroOrange = Color(red: 1.0, green: 0.48, blue: 0.0)
}

extension UIColor {
    static let neuroGold = UIColor(red: 1.0, green: 0.66, blue: 0.0, alpha: 1)
}
