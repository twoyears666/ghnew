import Foundation
import Combine

/// Global in-app settings (dark mode + language). Persisted to UserDefaults.
/// Deliberately NOT @MainActor-isolated so the static `Theme.palette` accessor
/// (which reads `isDarkMode`) stays callable from plain contexts like view bodies.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "ghSettings.dark")
        }
    }

    @Published var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "ghSettings.lang")
        }
    }

    /// Used as a SwiftUI `.id()` to force a full re-render on setting change.
    var themeSignature: String {
        "\(isDarkMode ? "d" : "l")-\(language.rawValue)"
    }

    enum Language: String, CaseIterable {
        case zh
        case en
        var label: String { self == .zh ? "中文" : "English" }
    }

    private init() {
        let def = UserDefaults.standard
        let sysLang = Locale.current.language.languageCode?.identifier
        isDarkMode = def.bool(forKey: "ghSettings.dark")
        language = Language(rawValue: def.string(forKey: "ghSettings.lang") ?? "") ??
                   (sysLang == "zh" ? .zh : .en)
    }
}