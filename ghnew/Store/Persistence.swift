import Foundation

extension String {
    /// Parse a GitHub ISO8601 timestamp (with or without fractional seconds).
    var ghDate: Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: self) { return d }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: self) { return d }
        return nil
    }
}

/// Human readable time helper matching the requested card semantics:
/// minutes ago (<1h) / hours ago (1–2h) / today at HH:mm / "Sep 22 at 15:00 GMT+10".
enum TimeFormat {
    static func relative(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var cal = Calendar.current
        cal.timeZone = timeZone
        let secs = now.timeIntervalSince(date)
        if secs < 3600 {
            let m = max(1, Int(secs / 60))
            return "\(m) minute\(m == 1 ? "" : "s") ago"
        }
        if secs < 7200 {
            let h = Int(secs / 3600)
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        }
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.timeZone = timeZone
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "'today at' HH:mm"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d ' at ' HH:mm"
        var s = f.string(from: date)
        let gmt = timeZone.secondsFromGMT(for: date)
        let h = gmt / 3600
        let m = (Int(abs(gmt)) % 3600) / 60
        let sign = h >= 0 ? "GMT+" : "GMT-"
        s += " \(sign)\(abs(h)):\(String(format: "%02d", m))"
        return s
    }

    static func duration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "—" }
        if interval < 60 { return "\(Int(interval))s" }
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        let s = Int(interval) % 60
        if h > 0 { return "\(h)h \(m)min \(s)s" }
        if m > 0 { return "\(m)min \(s)s" }
        return "\(s)s"
    }
}

/// File persistence: repos live in Documents/repos.json; each message is its own
/// JSON file under Documents/messages/<id>.json.
enum Persistence {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var messagesDirectory: URL {
        documentsDirectory.appendingPathComponent("messages", isDirectory: true)
    }
    private static var reposURL: URL {
        documentsDirectory.appendingPathComponent("repos.json")
    }
    private static let userKey = "ghUser"

    // MARK: - Login user

    static func loadUser() -> GitHubUser? {
        guard let data = UserDefaults.standard.data(forKey: userKey),
              let u = try? JSONDecoder().decode(GitHubUser.self, from: data) else { return nil }
        return u
    }

    static func saveUser(_ user: GitHubUser?) {
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userKey)
        }
    }

    static func loadRepos() -> [TrackedRepo] {
        guard let data = try? Data(contentsOf: reposURL) else { return [] }
        return (try? JSONDecoder().decode([TrackedRepo].self, from: data)) ?? []
    }

    static func saveRepos(_ repos: [TrackedRepo]) {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        try? data.write(to: reposURL, options: .atomic)
    }

    static func saveMessage(_ msg: GHMessage) {
        try? FileManager.default.createDirectory(at: messagesDirectory,
                                                 withIntermediateDirectories: true)
        let url = messagesDirectory.appendingPathComponent("\(msg.id).json")
        if let data = try? JSONEncoder().encode(msg) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func deleteMessage(_ msg: GHMessage) {
        let url = messagesDirectory.appendingPathComponent("\(msg.id).json")
        try? FileManager.default.removeItem(at: url)
    }

    static func loadMessages() -> [GHMessage] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: messagesDirectory.path) else {
            return []
        }
        var out: [GHMessage] = []
        for file in files where file.hasSuffix(".json") {
            let url = messagesDirectory.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                  let msg = try? JSONDecoder().decode(GHMessage.self, from: data) else { continue }
            out.append(msg)
        }
        return out
    }
}