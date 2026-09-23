import Foundation

/// Minimal GitHub REST API client used by the tracker.
final class GitHubAPI {
    static let shared = GitHubAPI()
    private let base = "https://api.github.com"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Optional personal access token. When set, authenticated rate limits apply.
    var token: String? {
        didSet {
            if let t = token, !t.isEmpty {
                UserDefaults.standard.set(t, forKey: "ghToken")
            } else {
                token = nil
                UserDefaults.standard.removeObject(forKey: "ghToken")
            }
        }
    }

    init() {
        if let t = UserDefaults.standard.string(forKey: "ghToken"), !t.isEmpty {
            token = t
        }
    }

    private func makeRequest(_ path: String) -> URLRequest {
        var url = URL(string: base + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("ghnew/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func validateRepo(owner: String, name: String) async throws -> GHRepo {
        let path = "/repos/\(owner)/\(name)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let (data, resp) = try await session.data(for: makeRequest(path))
        try Self.throwIfErrors(data: data, response: resp)
        let repo = try JSONDecoder().decode(GHRepo.self, from: data)
        return repo
    }

    func fetchReleases(owner: String, name: String) async throws -> [GHRelease] {
        let path = "/repos/\(owner)/\(name)/releases?per_page=30"
        let (data, resp) = try await session.data(for: makeRequest(path))
        try Self.throwIfErrors(data: data, response: resp)
        return try JSONDecoder().decode([GHRelease].self, from: data)
    }

    func fetchRuns(owner: String, name: String) async throws -> [GHRun] {
        let path = "/repos/\(owner)/\(name)/actions/runs?per_page=30"
        let (data, resp) = try await session.data(for: makeRequest(path))
        try Self.throwIfErrors(data: data, response: resp)
        let wrapped = try JSONDecoder().decode(RunListResponse.self, from: data)
        return wrapped.workflow_runs
    }

    private struct RunListResponse: Codable {
        let total_count: Int
        let workflow_runs: [GHRun]
    }

    private static func throwIfErrors(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "? status \(http.statusCode)"
            throw APIError.http(code: http.statusCode, detail: String(msg.prefix(300)))
        }
    }
}

enum APIError: LocalizedError {
    case badResponse
    case http(code: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Invalid server response."
        case .http(let code, let detail):
            return "GitHub API error \(code): \(detail)"
        }
    }
}