import Foundation

// MARK: - Tracked repo

struct TrackedRepo: Codable, Identifiable, Equatable {
    var id: String { "\(owner)/\(name)" }
    var owner: String
    var name: String
    var watchRelease: Bool
    var watchAction: Bool
    var defaultBranch: String?
    var lastSeenRelease: Int?   // highest GitHub release id already recorded
    var lastSeenRun: Int?       // highest workflow run id already recorded
    var addedAt: Date

    init(owner: String, name: String, watchRelease: Bool, watchAction: Bool,
         defaultBranch: String? = nil, lastSeenRelease: Int? = nil,
         lastSeenRun: Int? = nil, addedAt: Date = Date()) {
        self.owner = owner
        self.name = name
        self.watchRelease = watchRelease
        self.watchAction = watchAction
        self.defaultBranch = defaultBranch
        self.lastSeenRelease = lastSeenRelease
        self.lastSeenRun = lastSeenRun
        self.addedAt = addedAt
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