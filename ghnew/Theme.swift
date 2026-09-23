import SwiftUI

/// PCL-style light theme colors (blue top bar, light blue-gray page background,
/// white cards with light-blue-gray borders, dark text). No dark theme.
enum Theme {
    // Page / column background (light blue-gray)
    static let pageBackground  = Color(hex: 0xEEF1F6)
    static let columnBackground = Color(hex: 0xE9EDF3)

    // Repo row states
    static let repoRowSelected = Color(hex: 0xC7D0DC)  // deeper gray, selected
    static let repoRowNormal   = Color(hex: 0xE9EDF3)  // light gray = column bg

    // Cards
    static let cardBorder    = Color(hex: 0xD9E4F0)
    static let cardShadow    = Color(hex: 0x000000).opacity(0.08)

    // Text
    static let textPrimary   = Color(hex: 0x26292E)   // near black
    static let textSecondary = Color(hex: 0x747B86)   // gray
    static let textMuted     = Color(hex: 0x9AA1AB)

    // Accent
    static let accentBlue    = Color(hex: 0x3B82F6)
    // Branch badge
    static let branchBlueBg   = Color(hex: 0xDDECFF)
    static let branchBlueText = Color(hex: 0x1F6FEB)

    // Markdown code
    static let codeBackground = Color(hex: 0xE8EDF2)
    static let codeText       = Color(hex: 0x9B1C4B)

    // Run outcome colors (match GitHub's success/failure semantics)
    static let successGreen  = Color(hex: 0x1B9C5E)
    static let failRed       = Color(hex: 0xD3453A)
    static let releaseGreen  = Color(hex: 0x2EA44F)
    static let prereleaseBrown = Color(hex: 0x9A6700)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: alpha)
    }
}

