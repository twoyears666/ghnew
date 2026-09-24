import Foundation

// MARK: - Tracked repo

struct TrackedRepo: Codable, Identifiable, Equatable {
    var id: String { "\(owner)/\(name)" }
    var owner: String
    var name: String
    var watchRelease: Bool
    var watchAction: Bool
    /// Whether new releases/actions should post a Notification Center banner.
    var notify: Bool
    var defaultBranch: String?
    var lastSeenRelease: Int?   // highest GitHub release id already recorded
    var lastSeenRun: Int?       // highest workflow run id already recorded
    var addedAt: Date

    init(owner: String, name: String, watchRelease: Bool, watchAction: Bool,
         notify: Bool = true, defaultBranch: String? = nil,
         lastSeenRelease: Int? = nil, lastSeenRun: Int? = nil, addedAt: Date = Date()) {
        self.owner = owner
        self.name = name
        self.watchRelease = watchRelease
        self.watchAction = watchAction
        self.notify = notify
        self.defaultBranch = defaultBranch
        self.lastSeenRelease = lastSeenRelease
        self.lastSeenRun = lastSeenRun
        self.addedAt = addedAt
    }

    // Manual decoding so older persisted files (without `notify`) still load.
    private enum CodingKeys: String, CodingKey {
        case owner, name, watchRelease, watchAction, notify,
             defaultBranch, lastSeenRelease, lastSeenRun, addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owner = try c.decode(String.self, forKey: .owner)
        name = try c.decode(String.self, forKey: .name)
        watchRelease = try c.decodeIfPresent(Bool.self, forKey: .watchRelease) ?? true
        watchAction = try c.decodeIfPresent(Bool.self, forKey: .watchAction) ?? true
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        defaultBranch = try c.decodeIfPresent(String.self, forKey: .defaultBranch)
        lastSeenRelease = try c.decodeIfPresent(Int.self, forKey: .lastSeenRelease)
        lastSeenRun = try c.decodeIfPresent(Int.self, forKey: .lastSeenRun)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

// MARK: - Message (a release or an action run)

enum MessageKind: String, Codable, Equatable {
    case release
    case action
}

struct GHMessage: Codable, Identifiable, Equatable {
    var id: String
    var repoID: String           // "owner/name"
    var kind: MessageKind
    var createdAt: Date

    // Release fields
    var releaseTitle: String?
    var releaseTag: String?
    var releaseBody: String?
    var isPrerelease: Bool = false
    var releaseURL: String?

    // Action fields
    var actionTitle: String?
    var runNumber: Int?
    var runID: Int? = nil
    var commitID: String?
    var actor: String?
    var branch: String?
    var runStatus: String?          // queued / in_progress / completed
    var runConclusion: String?      // success / failure / cancelled / ...
    var duration: TimeInterval?
    var actionsURL: String?

    // Pills / computed

    /// Release pill label derived from the tag, per GitHub tagging conventions.
    var releaseBadge: String {
        let t = (releaseTag ?? "").lowercased()
        if t.contains("beta") { return "beta release" }
        if t.contains("alpha") { return "alpha release" }
        if t.contains("rc") || t.contains("preview") { return "prerelease" }
        if isPrerelease { return "prerelease" }
        return "release"
    }

    var isReleaseBadgeGreen: Bool {
        releaseBadge == "release" || releaseBadge.contains("stable")
    }
}

// MARK: - GitHub API decoding models

struct GHRepo: Codable {
    let full_name: String
    let default_branch: String?
    let isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case full_name
        case default_branch
        case isPrivate = "private"
    }
}

struct GHRelease: Codable, Identifiable {
    let id: Int
    let tag_name: String?
    let name: String?
    let body: String?
    let prerelease: Bool?
    let html_url: String?
    let published_at: String?
}

struct GHAuthor: Codable {
    let login: String?
    let avatar_url: String?
}

/// The currently authenticated user (from GET /user).
struct GitHubUser: Codable, Equatable {
    var login: String?
    var avatar_url: String?
}

struct GHRun: Codable, Identifiable {
    let id: Int
    let display_title: String?
    let run_number: Int?
    let status: String?
    let conclusion: String?
    let head_sha: String?
    let head_branch: String?
    let created_at: String?
    let updated_at: String?
    let run_started_at: String?
    let triggering_actor: GHAuthor?
    let actor: GHAuthor?
    let html_url: String?
}

// MARK: - Artifacts (Actions), assets (Releases), jobs & annotations

/// A single Actions artifact. Used by GET /repos/{o}/{n}/actions/artifacts.
struct GHArtifact: Codable, Identifiable {
    let id: Int
    let name: String?
    let size_in_bytes: Int64?
    let archive_download_url: String?
    let expired: Bool?
    let created_at: String?
    let workflow_run: GHWorkflowRunRef?
}

struct GHWorkflowRunRef: Codable {
    let id: Int?
}

/// A release asset. Used by GET /repos/{o}/{n}/releases/{id}/assets.
struct GHAsset: Codable, Identifiable {
    let id: Int
    let name: String?
    let size: Int64?
    let browser_download_url: String?
    let content_type: String?
}

/// A workflow job. Used by GET /repos/{o}/{n}/actions/runs/{id}/jobs.
struct GHJob: Codable {
    let id: Int?
    let name: String?
    let status: String?
    let conclusion: String?
}

/// A check run reference. Used by GET /repos/{o}/{n}/commits/{sha}/check-runs.
struct GHCheckRun: Codable {
    let id: Int?
    let conclusion: String?
    let name: String?
    let annotations_url: String?
}

/// A check-run annotation. Used by GET {annotations_url}.
struct GHAnnotation: Codable {
    let message: String?
    let annotation_level: String?
    let path: String?
    let title: String?
}

/// One entry of GET /user/repos (used for the first-login repo picker).
struct GHRepoListItem: Codable, Identifiable {
    let id: Int
    let full_name: String
    let owner: GHOwnerRef?
    let default_branch: String?
    var ownerLogin: String { owner?.login ?? full_name.split(separator: "/").first.map(String.init) ?? "" }
    var repoName: String { full_name.split(separator: "/").last.map(String.init) ?? "" }
}

struct GHOwnerRef: Codable {
    let login: String?
}