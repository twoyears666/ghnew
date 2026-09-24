import SwiftUI

/// Theme palette descriptor. Default is the PCL-style light theme; switching
/// `AppSettings.shared.isDarkMode` flips to the dark palette.
struct ThemePalette {
    let pageBackground: Color
    let columnBackground: Color
    let repoRowSelected: Color
    let repoRowNormal: Color
    let cardFill: Color
    let cardBorder: Color
    let cardShadow: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let accentBlue: Color
    let branchBlueBg: Color
    let branchBlueText: Color
    let codeBackground: Color
    let codeText: Color
    let successGreen: Color
    let failRed: Color
    let releaseGreen: Color
    let prereleaseBrown: Color
}

enum ThemePalettes {
    static let light = ThemePalette(
        pageBackground: Color(hex: 0xEEF1F6),
        columnBackground: Color(hex: 0xE9EDF3),
        repoRowSelected: Color(hex: 0xC7D0DC),
        repoRowNormal: Color(hex: 0xE9EDF3),
        cardFill: .white,
        cardBorder: Color(hex: 0xD9E4F0),
        cardShadow: Color(hex: 0x000000).opacity(0.08),
        textPrimary: Color(hex: 0x26292E),
        textSecondary: Color(hex: 0x747B86),
        textMuted: Color(hex: 0x9AA1AB),
        accentBlue: Color(hex: 0x3B82F6),
        branchBlueBg: Color(hex: 0xDDECFF),
        branchBlueText: Color(hex: 0x1F6FEB),
        codeBackground: Color(hex: 0xE8EDF2),
        codeText: Color(hex: 0x9B1C4B),
        successGreen: Color(hex: 0x1B9C5E),
        failRed: Color(hex: 0xD3453A),
        releaseGreen: Color(hex: 0x2EA44F),
        prereleaseBrown: Color(hex: 0x9A6700)
    )

    static let dark = ThemePalette(
        pageBackground: Color(hex: 0x14161B),
        columnBackground: Color(hex: 0x1A1D24),
        repoRowSelected: Color(hex: 0x35404F),
        repoRowNormal: Color(hex: 0x1A1D24),
        cardFill: Color(hex: 0x21262D),
        cardBorder: Color(hex: 0x3A4150),
        cardShadow: Color(hex: 0x000000).opacity(0.4),
        textPrimary: Color(hex: 0xEEF0F4),
        textSecondary: Color(hex: 0xA8B0BD),
        textMuted: Color(hex: 0x7A838F),
        accentBlue: Color(hex: 0x58A6FF),
        branchBlueBg: Color(hex: 0x1F3A5F),
        branchBlueText: Color(hex: 0x6CB6FF),
        codeBackground: Color(hex: 0x1A1F29),
        codeText: Color(hex: 0xE3988B),
        successGreen: Color(hex: 0x3FB950),
        failRed: Color(hex: 0xF85149),
        releaseGreen: Color(hex: 0x3FB950),
        prereleaseBrown: Color(hex: 0xD29922)
    )
}

/// Dynamic theme colors. They read the current palette each time they are
/// accessed, so a single `.id(settings.themeSignature)` rebuild forces the whole
/// UI to adopt the new palette.
enum Theme {
    static var palette: ThemePalette {
        AppSettings.shared.isDarkMode ? ThemePalettes.dark : ThemePalettes.light
    }
    static var pageBackground: Color   { palette.pageBackground }
    static var columnBackground: Color { palette.columnBackground }
    static var repoRowSelected: Color  { palette.repoRowSelected }
    static var repoRowNormal: Color    { palette.repoRowNormal }
    static var cardFill: Color         { palette.cardFill }
    static var cardBorder: Color       { palette.cardBorder }
    static var cardShadow: Color       { palette.cardShadow }
    static var textPrimary: Color      { palette.textPrimary }
    static var textSecondary: Color    { palette.textSecondary }
    static var textMuted: Color        { palette.textMuted }
    static var accentBlue: Color       { palette.accentBlue }
    static var branchBlueBg: Color     { palette.branchBlueBg }
    static var branchBlueText: Color   { palette.branchBlueText }
    static var codeBackground: Color   { palette.codeBackground }
    static var codeText: Color         { palette.codeText }
    static var successGreen: Color     { palette.successGreen }
    static var failRed: Color          { palette.failRed }
    static var releaseGreen: Color     { palette.releaseGreen }
    static var prereleaseBrown: Color  { palette.prereleaseBrown }
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