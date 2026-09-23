import Foundation
import UserNotifications

enum RepoError: LocalizedError {
    case alreadyAdded
    var errorDescription: String? {
        switch self {
        case .alreadyAdded: return "This repository is already being tracked."
        }
    }
}

/// Central observable store: holds the tracked repo list and the message inbox,
/// persists them to Documents, and periodically polls GitHub for new items.
@MainActor
final class AppStore: ObservableObject {
    @Published var repos: [TrackedRepo] = []
    @Published var messages: [GHMessage] = []       // all repos combined, newest first
    @Published var selectedRepoID: String?
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var showAddRepo = false

    private let api = GitHubAPI.shared
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 300    // 5 minutes

    var selectedRepo: TrackedRepo? {
        repos.first { $0.id == selectedRepoID }
    }

    var messagesForSelected: [GHMessage] {
        guard let id = selectedRepoID else { return [] }
        return messages.filter { $0.repoID == id }
                       .sorted { $0.createdAt > $1.createdAt }
    }

    init() {
        repos = Persistence.loadRepos()
        messages = Persistence.loadMessages().sorted { $0.createdAt > $1.createdAt }
        if repos.first(where: { $0.id == selectedRepoID }) == nil {
            selectedRepoID = repos.first?.id
        }
        startPolling()
    }

    // MARK: - Repo management

    func addRepo(owner: String, name: String, watchRelease: Bool, watchAction: Bool) async throws {
        let cleanedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedOwner.isEmpty, !cleanedName.isEmpty else {
            throw APIError.badResponse   // handled as message
        }
        let key = "\(cleanedOwner.lowercased())/\(cleanedName.lowercased())"
        guard !repos.contains(where: { $0.id.lowercased() == key }) else {
            throw RepoError.alreadyAdded
        }
        let gh = try await api.validateRepo(owner: cleanedOwner, name: cleanedName)
        let actualName = gh.full_name.split(separator: "/").map(String.init).last ?? cleanedName
        let tracked = TrackedRepo(owner: cleanedOwner, name: actualName,
                                  watchRelease: watchRelease, watchAction: watchAction,
                                  defaultBranch: gh.default_branch)
        repos.append(tracked)
        Persistence.saveRepos(repos)
        if selectedRepoID == nil { selectedRepoID = tracked.id }
        await refreshRepo(tracked)
    }

    func removeRepo(at offsets: IndexSet) {
        let removed = offsets.map { repos[$0] }
        repos.remove(atOffsets: offsets)
        Persistence.saveRepos(repos)
        for r in removed {
            if selectedRepoID == r.id { selectedRepoID = repos.first?.id }
            // drop its persisted messages
            for m in messages where m.repoID == r.id { Persistence.deleteMessage(m) }
            messages.removeAll { $0.repoID == r.id }
        }
    }

    func select(_ id: String) { selectedRepoID = id }

    // MARK: - Refresh / polling

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        for repo in repos {
            await refreshRepo(repo)
        }
        isRefreshing = false
    }

    func refreshRepo(_ repo: TrackedRepo) async {
        var updated = repo
        do {
            if repo.watchRelease {
                let releases = try await api.fetchReleases(owner: repo.owner, name: repo.name)
                updated.lastSeenRelease = processReleases(releases, repo: repo)
            }
            if repo.watchAction {
                let runs = try await api.fetchRuns(owner: repo.owner, name: repo.name)
                updated.lastSeenRun = processRuns(runs, repo: repo)
            }
            if let idx = repos.firstIndex(where: { $0.id == repo.id }) {
                repos[idx] = updated
                Persistence.saveRepos(repos)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.pollInterval ?? 300) * 1_000_000_000)
                await self?.refreshAll()
            }
        }
    }

    // MARK: - Ingest

    private func processReleases(_ releases: [GHRelease], repo: TrackedRepo) -> Int? {
        var maxID = repo.lastSeenRelease
        let base = "https://github.com/\(repo.owner)/\(repo.name)"
        for rel in releases {
            let id = "r-\(repo.owner.lowercased())-\(repo.name.lowercased())-\(rel.id)"
            let msg = GHMessage(id: id,
                                repoID: repo.id,
                                kind: .release,
                                createdAt: rel.published_at?.ghDate ?? Date(),
                                releaseTitle: rel.name?.nilIfEmpty ?? rel.tag_name ?? "Release",
                                releaseTag: rel.tag_name,
                                releaseBody: rel.body,
                                isPrerelease: rel.prerelease ?? false,
                                releaseURL: rel.html_url ?? "\(base)/releases")
            if insertMessageIfNew(msg) {
                maxID = max(maxID ?? 0, rel.id)
            }
        }
        return maxID
    }

    private func processRuns(_ runs: [GHRun], repo: TrackedRepo) -> Int? {
        var maxID = repo.lastSeenRun
        let base = "https://github.com/\(repo.owner)/\(repo.name)"
        for run in runs {
            let id = "a-\(repo.owner.lowercased())-\(repo.name.lowercased())-\(run.id)"
            let start = run.run_started_at?.ghDate ?? run.created_at?.ghDate ?? Date()
            var duration: TimeInterval?
            if run.status == "completed", let end = run.updated_at?.ghDate {
                duration = max(0, end.timeIntervalSince(start))
            }
            let actor = run.triggering_actor?.login ?? run.actor?.login ?? ""
            let msg = GHMessage(id: id,
                                repoID: repo.id,
                                kind: .action,
                                createdAt: start,
                                actionTitle: run.display_title?.nilIfEmpty ?? "Workflow run",
                                runNumber: run.run_number,
                                commitID: run.head_sha.map { String($0.prefix(7)) } ?? "",
                                actor: actor.nilIfEmpty,
                                branch: run.head_branch,
                                runStatus: run.status,
                                runConclusion: run.conclusion,
                                duration: duration,
                                actionsURL: run.html_url ?? "\(base)/actions/runs/\(run.id)")
            if insertMessageIfNew(msg) {
                maxID = max(maxID ?? 0, run.id)
            }
        }
        return maxID
    }

    @discardableResult
    private func insertMessageIfNew(_ msg: GHMessage) -> Bool {
        guard !messages.contains(where: { $0.id == msg.id }) else { return false }
        messages.append(msg)
        Persistence.saveMessage(msg)
        postNotification(for: msg)
        return true
    }

    private func postNotification(for msg: GHMessage) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            if msg.kind == .release {
                content.title = "New release"
                content.body = "\(msg.repoID) · \(msg.releaseTitle ?? "")"
            } else {
                content.title = "Action \(msg.runConclusion ?? msg.runStatus ?? "")"
                content.body = "\(msg.repoID) · \(msg.releaseTitle ?? msg.actionTitle ?? "")"
            }
            content.sound = .default
            let req = UNNotificationRequest(identifier: msg.id, content: content, trigger: nil)
            center.add(req)
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}