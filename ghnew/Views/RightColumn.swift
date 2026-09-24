import SwiftUI

/// Right column — shows the detail for the selected message (release or action),
/// including the changelog / progress / annotations and the downloadable artifacts.
struct RightColumn: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var downloads = DownloadManager.shared

    @State private var assets: [GHAsset] = []
    @State private var artifacts: [GHArtifact] = []
    @State private var annotations: [GHAnnotation] = []
    @State private var showLogin = false

    var body: some View {
        Group {
            if let msg = store.selectedMessage {
                detail(for: msg)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.columnBackground)
        .sheet(isPresented: $showLogin) { LoginSheet().environmentObject(store) }
        .task(id: store.selectedMessageID) {
            await refreshLoop()
        }
    }

    // MARK: - Loading

    /// Keeps the on-screen details fresh: loads on entry and, while a running
    /// action is selected, polls its status (and details) every 20 s until the
    /// run finishes. Task(id:) cancels this when the selection or the page goes away.
    private func refreshLoop() async {
        while !Task.isCancelled {
            // Refresh live status first so a just-completed run is reflected before
            // artifacts/annotations are (re)loaded.
            if let msg = store.selectedMessage, msg.kind == .action {
                await store.refreshActionStatus(for: msg)
            }
            await load()
            guard let msg = store.selectedMessage,
                  msg.kind == .action,
                  msg.runStatus != "completed" else { return }
            try? await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }

    private func load() async {
        assets = []
        artifacts = []
        annotations = []
        guard let msg = store.selectedMessage, let repo = store.selectedRepo else { return }
        let owner = repo.owner, name = repo.name
        let api = GitHubAPI.shared
        switch msg.kind {
        case .release:
            if let tag = msg.releaseTag,
               let rid = try? await api.findRelease(owner: owner, name: name, tag: tag) {
                assets = (try? await api.fetchReleaseAssets(owner: owner, name: name, releaseID: rid)) ?? []
            }
        case .action:
            // Only a run that actually concluded successfully has downloadable
            // artifacts from that run; a failed/cancelled/in-flight run should not
            // show artifacts that don't (reliably) exist for it.
            if let runID = msg.runID, msg.runConclusion == "success" {
                let all = (try? await api.fetchArtifacts(owner: owner, name: name)) ?? []
                artifacts = all.filter { $0.workflow_run?.id == runID }
            }
            if let sha = msg.commitID, !sha.isEmpty {
                var collected: [GHAnnotation] = []
                let checks = (try? await api.fetchCheckRuns(owner: owner, name: name, headSHA: sha)) ?? []
                for c in checks {
                    if let u = c.annotations_url, let url = URL(string: u) {
                        let anns = (try? await api.fetchAnnotations(url: url)) ?? []
                        collected.append(contentsOf: anns)
                    }
                }
                annotations = collected
            }
        }
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(Theme.textMuted)
            Text(Localization.L("selectReleaseOrRun"))
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
            Spacer()
        }
    }

    // MARK: - Detail

    private func detail(for msg: GHMessage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if msg.kind == .release {
                    releaseHeader(msg)
                } else {
                    actionHeader(msg)
                }

                if msg.kind == .release {
                    section(Localization.L("changelog")) {
                        if let body = msg.releaseBody?.nilIfEmpty, !body.isEmpty {
                            MarkdownView(markdown: body, fontSize: 13)
                        } else {
                            hint(Localization.L("noBody"))
                        }
                    }
                    section(Localization.L("assets")) {
                        if assets.isEmpty {
                            hint(Localization.L("noArtifacts"))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(assets) { a in
                                    DownloadRow(id: "rel-\(repoKey(msg))-\(a.id)",
                                                name: a.name ?? "asset", size: a.size,
                                                url: a.browser_download_url.flatMap(URL.init),
                                                needsAuth: false,
                                                downloads: downloads,
                                                onLogin: { showLogin = true })
                                    Divider()
                                }
                            }
                        }
                    }
                } else {
                    section(Localization.L("progress")) {
                        ActionProgressView(message: msg)
                    }
                    section(Localization.L("annotations")) {
                        if annotations.isEmpty {
                            hint(Localization.L("noAnnotations"))
                        } else {
                            VStack(spacing: 6) {
                                ForEach(Array(annotations.enumerated()), id: \.offset) { _, w in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(Theme.prereleaseBrown)
                                            .font(.system(size: 12))
                                        Text(w.message ?? w.title ?? "")
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                    section(Localization.L("artifacts")) {
                        if artifacts.isEmpty {
                            hint(Localization.L("noArtifacts"))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(artifacts) { ar in
                                    DownloadRow(id: "act-\(repoKey(msg))-\(ar.id)",
                                                name: ar.name ?? "artifact", size: ar.size_in_bytes,
                                                url: ar.archive_download_url.flatMap(URL.init),
                                                needsAuth: true,
                                                downloads: downloads,
                                                onLogin: { showLogin = true })
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .padding(.bottom, 24)
        }
    }

    private func repoKey(_ msg: GHMessage) -> String {
        msg.repoID.lowercased().replacingOccurrences(of: "/", with: "-")
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(Theme.textMuted)
    }

    private func releaseHeader(_ msg: GHMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(msg.releaseTitle ?? "Release")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button {
                    openExternal(msg.releaseURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accentBlue)
                }
                .buttonStyle(.plain)
                if let url = msg.releaseURL.flatMap(URL.init) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                PillBadge(text: msg.releaseBadge,
                          color: msg.isReleaseBadgeGreen ? Theme.releaseGreen : Theme.prereleaseBrown)
                if let tag = msg.releaseTag {
                    Text(tag).font(.system(size: 12)).foregroundColor(Theme.textSecondary)
                }
            }
        }
    }

    private func actionHeader(_ msg: GHMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RunStatusView(message: msg)
            VStack(alignment: .leading, spacing: 4) {
                Text(msg.actionTitle?.nilIfEmpty ?? "Workflow run")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("#\(msg.runNumber ?? 0)").font(.system(size: 12)).foregroundColor(Theme.textSecondary)
                    BranchBadge(name: msg.branch)
                    Spacer()
                }
            }
            Spacer(minLength: 0)
            if let url = msg.actionsURL.flatMap(URL.init) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accentBlue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textSecondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A progress bar for a workflow run: colored by outcome when complete, animated
/// while running. GitHub exposes no byte-level run progress, so running runs show
/// an indeterminate animated bar.
struct ActionProgressView: View {
    let message: GHMessage

    private var isDone: Bool { message.runStatus == "completed" }
    private var fillColor: Color {
        if let c = message.runConclusion, c == "success" { return Theme.successGreen }
        if isDone { return Theme.failRed }
        return Theme.accentBlue
    }
    private var statusText: String {
        if isDone { return message.runConclusion?.capitalized ?? "Completed" }
        switch message.runStatus {
        case "queued", "pending": return "Queued"
        default: return "In progress"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(fillColor)
                Spacer()
                Text(TimeFormat.duration(message.duration ?? 0))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardBorder)
                    if isDone {
                        Capsule().fill(fillColor)
                            .frame(width: geo.size.width)
                    } else {
                        Capsule()
                            .fill(fillColor)
                            .frame(width: geo.size.width * 0.4)
                            .offset(x: marquee ? geo.size.width * 0.6 : 0)
                    }
                }
            }
            .frame(height: 8)
            .padding(.top, 2)
        }
        .onAppear {
            guard !isDone else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                marquee = true
            }
        }
    }

    @State private var marquee = false
}

/// A single downloadable row: name + size on the left, download/progress/done on
/// the right. When an artifact requires login but the user is logged out, it shows
/// a prompt to log in.
struct DownloadRow: View {
    let id: String
    let name: String
    let size: Int64?
    let url: URL?
    let needsAuth: Bool
    @ObservedObject var downloads: DownloadManager
    let onLogin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: needsAuth ? "archivebox" : "paperclip")
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                let sz = DownloadManager.bytesString(size)
                if !sz.isEmpty {
                    Text(sz).font(.system(size: 11)).foregroundColor(Theme.textMuted)
                }
            }
            Spacer(minLength: 8)
            if let item = downloads.item(for: id) {
                DownloadStateView(item: item, downloads: downloads, onLogin: onLogin)
            } else {
                startButton
            }
        }
        .padding(.vertical, 4)
    }

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle").font(.system(size: 13))
                Text(Localization.L("download")).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Theme.accentBlue)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    private func start() {
        guard let url else { return }
        downloads.download(key: id, name: name, size: size, url: url, needsAuth: needsAuth)
    }
}

/// Renders the live state of an already-started download.
struct DownloadStateView: View {
    @ObservedObject var item: DownloadItem
    let downloads: DownloadManager
    let onLogin: () -> Void

    var body: some View {
        switch item.state {
        case .idle:
            Button { downloads.startRetry(item) } label: { dlLabel("download", "arrow.down.circle") }
        case .downloading:
            HStack(spacing: 6) {
                ProgressView(value: item.progress)
                    .frame(width: 70)
                    .tint(Theme.accentBlue)
                Text("\(Int(item.progress * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
        case .done:
            Button { downloads.reveal(item) } label: { dlLabel("downloaded", "checkmark.circle.fill").foregroundColor(Theme.successGreen) }
        case .failed:
            Button { downloads.startRetry(item) } label: { dlLabel("downloadFailed", "arrow.clockwise").foregroundColor(Theme.failRed) }
        case .authRequired:
            Button(action: onLogin) { dlLabel("loginToGetArtifacts", "lock.fill").foregroundColor(Theme.accentBlue) }
        }
    }

    private func dlLabel(_ key: String, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11))
            Text(Localization.L(key)).font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(Theme.accentBlue)
    }
}