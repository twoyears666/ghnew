import Foundation

/// A GitHub download mirror ("中转") node. Mirrors are the public ones listed on
/// fastlist.pages.dev; ghnew only reuses the idea, not FastList's UI.
struct RelayNode: Identifiable, Hashable {
    let host: String
    var id: String { host }
}

/// Latency bucket used by the "测试节点延迟" readout.
enum LatencyGrade {
    case fast, medium, slow, failed

    var label: String {
        switch self {
        case .fast: return Localization.L("latencyFast")
        case .medium: return Localization.L("latencyMedium")
        case .slow: return Localization.L("latencySlow")
        case .failed: return Localization.L("latencyFail")
        }
    }
}

/// Download acceleration helpers: relay-node catalog, URL rewriting and a
/// best-effort latency probe.
enum Accelerator {
    /// Public mirrors, in the order FastList lists them.
    static let relayNodes: [RelayNode] = [
        RelayNode(host: "gh-proxy.com"),
        RelayNode(host: "ghproxy.net"),
        RelayNode(host: "edgeone.gh-proxy.com"),
        RelayNode(host: "cdn.gh-proxy.com"),
        RelayNode(host: "hk.gh-proxy.com"),
        RelayNode(host: "gh.llkk.cc"),
        RelayNode(host: "ghproxy.fangkuai.fun"),
        RelayNode(host: "ghproxy.imciel.com"),
        RelayNode(host: "ui.ghproxy.cc"),
        RelayNode(host: "gitproxy.click"),
        RelayNode(host: "ghproxy.link"),
        RelayNode(host: "iacc.eu.org"),
        RelayNode(host: "gh.jasonzeng.dev"),
        RelayNode(host: "gh-proxy.org"),
        RelayNode(host: "hk.gh-proxy.org"),
        RelayNode(host: "cdn.gh-proxy.org"),
        RelayNode(host: "edgeone.gh-proxy.org")
    ]

    static let defaultNodeHost = "gh-proxy.com"

    /// Rewrite an original URL so it is fetched through `host`
    /// (`https://{host}/{original}`).
    static func rewrite(_ original: URL, host: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "https://\(trimmed)/\(original.absoluteString)")
    }

    /// Fetch a small known file through the node and time it. Returns milliseconds
    /// or nil when the node fails. Best-effort: a failure is not fatal.
    static func measureLatency(host: String) async -> Int? {
        let target = "https://github.com/github/gitignore/raw/main/Swift.gitignore"
        guard let url = URL(string: "https://\(host)/\(target)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("ghnew/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        let started = Date()
        do {
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            return Int(Date().timeIntervalSince(started) * 1000)
        } catch {
            return nil
        }
    }

    /// Bucket a measured latency.
    static func grade(_ milliseconds: Int?) -> LatencyGrade {
        guard let ms = milliseconds else { return .failed }
        if ms < 100 { return .fast }
        if ms <= 300 { return .medium }
        return .slow
    }
}