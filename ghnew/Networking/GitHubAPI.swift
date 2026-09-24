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

    /// Optional personal access token, stored encrypted on this device.
    /// When set, authenticated rate limits apply.
    var token: String? {
        didSet {
            if let t = token, !t.isEmpty {
                SecretStore.storeToken(t)
            } else {
                token = nil
                SecretStore.clearToken()
            }
        }
    }

    init() {
        if let t = SecretStore.loadToken(), !t.isEmpty {
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

    /// Fetch the currently authenticated user (requires a valid token).
    func fetchUser() async throws -> GitHubUser? {
        let (data, resp) = try await session.data(for: makeRequest("/user"))
        try Self.throwIfErrors(data: data, response: resp)
        return try? JSONDecoder().decode(GitHubUser.self, from: data)
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

    // MARK: - Repos (for the first-login picker)

    func fetchUserRepos() async throws -> [GHRepoListItem] {
        let path = "/user/repos?per_page=100&sort=updated"
        let (data, resp) = try await session.data(for: makeRequest(path))
        try Self.throwIfErrors(data: data, response: resp)
        guard let list = try? JSONDecoder().decode([GHRepoListItem].self, from: data) else {
            return []
        }
        return list
    }

    // MARK: - Artifacts / assets / jobs / annotations

    func fetchArtifacts(owner: String, name: String) async throws -> [GHArtifact] {
        let list: ArtifactListResponse = try await get(path: "/repos/\(owner)/\(name)/actions/artifacts?per_page=50")
        return list.artifacts
    }

    func fetchReleaseAssets(owner: String, name: String, releaseID: Int) async throws -> [GHAsset] {
        try await get(path: "/repos/\(owner)/\(name)/releases/\(releaseID)/assets?per_page=50")
    }

    func fetchRunJobs(owner: String, name: String, runID: Int) async throws -> [GHJob] {
        let list: JobListResponse = try await get(path: "/repos/\(owner)/\(name)/actions/runs/\(runID)/jobs")
        return list.jobs
    }

    func fetchCheckRuns(owner: String, name: String, headSHA: String) async throws -> [GHCheckRun] {
        let list: CheckRunListResponse = try await get(path: "/repos/\(owner)/\(name)/commits/\(headSHA)/check-runs?per_page=50")
        return list.check_runs
    }

    func fetchAnnotations(url: URL) async throws -> [GHAnnotation] {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("ghnew/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await session.data(for: req)
        try Self.throwIfErrors(data: data, response: resp)
        return (try? JSONDecoder().decode([GHAnnotation].self, from: data)) ?? []
    }

    /// The release id matching `tag`, if found (assumes releases sorted newest-first).
    func findRelease(owner: String, name: String, tag: String) async throws -> Int? {
        let releases = try await fetchReleases(owner: owner, name: name)
        return releases.first(where: { ($0.tag_name ?? "") == tag })?.id
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let (data, resp) = try await session.data(for: makeRequest(path))
        try Self.throwIfErrors(data: data, response: resp)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode
        }
    }

    private struct ArtifactListResponse: Codable {
        let artifacts: [GHArtifact]
    }

    private struct JobListResponse: Codable {
        let jobs: [GHJob]
    }

    private struct CheckRunListResponse: Codable {
        let check_runs: [GHCheckRun]
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
    case decode
    case http(code: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Invalid server response."
        case .decode:
            return "Failed to decode server response."
        case .http(let code, let detail):
            return "GitHub API error \(code): \(detail)"
        }
    }
}