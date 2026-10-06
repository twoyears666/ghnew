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

    // MARK: - Acceleration 加速

    /// 中转总开关
    @Published var accelRelayEnabled: Bool {
        didSet { UserDefaults.standard.set(accelRelayEnabled, forKey: "ghSettings.accel.relay.enabled") }
    }
    /// 选中的中转节点 host
    @Published var accelRelayNode: String {
        didSet { UserDefaults.standard.set(accelRelayNode, forKey: "ghSettings.accel.relay.node") }
    }
    /// 中转是否作用于 Actions 产物（风险项，默认关）
    @Published var accelRelayIncludeArtifacts: Bool {
        didSet { UserDefaults.standard.set(accelRelayIncludeArtifacts, forKey: "ghSettings.accel.relay.artifacts") }
    }
    /// 并发总开关
    @Published var accelConcurrencyEnabled: Bool {
        didSet { UserDefaults.standard.set(accelConcurrencyEnabled, forKey: "ghSettings.accel.conc.enabled") }
    }
    /// 单文件分块数
    @Published var accelConcurrencyLevel: Int {
        didSet { UserDefaults.standard.set(accelConcurrencyLevel, forKey: "ghSettings.accel.conc.level") }
    }
    /// 并发是否作用于 Actions 产物（风险项，默认关）
    @Published var accelConcurrencyIncludeArtifacts: Bool {
        didSet { UserDefaults.standard.set(accelConcurrencyIncludeArtifacts, forKey: "ghSettings.accel.conc.artifacts") }
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

        accelRelayEnabled = def.bool(forKey: "ghSettings.accel.relay.enabled")
        let node = def.string(forKey: "ghSettings.accel.relay.node") ?? ""
        accelRelayNode = node.isEmpty ? Accelerator.defaultNodeHost : node
        accelRelayIncludeArtifacts = def.bool(forKey: "ghSettings.accel.relay.artifacts")
        accelConcurrencyEnabled = def.bool(forKey: "ghSettings.accel.conc.enabled")
        let level = def.integer(forKey: "ghSettings.accel.conc.level")
        accelConcurrencyLevel = level == 0 ? 4 : level
        accelConcurrencyIncludeArtifacts = def.bool(forKey: "ghSettings.accel.conc.artifacts")
    }
}