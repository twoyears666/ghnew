import SwiftUI

/// Left column: app title + tracked repo list + add button. The list is split
/// into a collapsible "pinned" group and a collapsible normal group; rows can be
/// long-pressed and dragged to reorder, and dragging one across the boundary
/// moves it between the two groups.
struct LeftColumn: View {
    @EnvironmentObject var store: AppStore
    @State private var editingRepo: TrackedRepo?
    @State private var pinnedCollapsed = false
    @State private var listCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ghnew")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 8)

            List {
                ForEach(entries) { entry in
                    row(for: entry)
                }
                .onMove(perform: moveEntries)

                RepoAddRow()
                    .onTapGesture { store.showAddRepo = true }
                    .modifier(PlainListRow())
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .background(Theme.columnBackground)

            Divider()
            LoginFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.columnBackground)
        .sheet(item: $editingRepo) { repo in
            RepoSettingsSheet(repo: repo).environmentObject(store)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for entry: RepoEntry) -> some View {
        switch entry {
        case .header(let group):
            RepoGroupHeader(group: group,
                            collapsed: isCollapsed(group)) { toggle(group) }
                .modifier(PlainListRow())
                .moveDisabled(true)
        case .repo(let repo):
            RepoRow(repo: repo, isSelected: store.selectedRepoID == repo.id)
                .onTapGesture { store.select(repo.id) }
                .contextMenu {
                    Button {
                        store.togglePinned(repo.id)
                    } label: {
                        Label(Localization.L(repo.pinned ? "unpinRepo" : "pinRepo"),
                              systemImage: repo.pinned ? "pin.slash" : "pin")
                    }
                    Button {
                        editingRepo = repo
                    } label: {
                        Label(Localization.L("repoSettings"),
                              systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        if let idx = store.repos.firstIndex(where: { $0.id == repo.id }) {
                            store.removeRepo(at: IndexSet(integer: idx))
                        }
                    } label: {
                        Label(Localization.L("remove"), systemImage: "trash")
                    }
                }
                .modifier(PlainListRow())
        }
    }

    // MARK: - Grouping

    /// Flattened rows: pinned header + pinned repos, then normal header + repos.
    /// A collapsed group keeps its header but drops its rows.
    private var entries: [RepoEntry] {
        var out: [RepoEntry] = [.header(.pinned)]
        if !pinnedCollapsed {
            out += store.repos.filter { $0.pinned }.map { .repo($0) }
        }
        out.append(.header(.list))
        if !listCollapsed {
            out += store.repos.filter { !$0.pinned }.map { .repo($0) }
        }
        return out
    }

    private func isCollapsed(_ group: RepoGroup) -> Bool {
        group == .pinned ? pinnedCollapsed : listCollapsed
    }

    private func toggle(_ group: RepoGroup) {
        if group == .pinned { pinnedCollapsed.toggle() } else { listCollapsed.toggle() }
    }

    /// Re-run the drag on the flattened rows, then read group membership back from
    /// where each repo landed relative to the "仓库列表" header.
    private func moveEntries(from: IndexSet, to: Int) {
        var work = entries
        work.move(fromOffsets: from, toOffset: to)
        guard let boundary = work.firstIndex(where: {
            if case .header(.list) = $0 { return true }
            return false
        }) else { return }

        var pinned: [String] = []
        var normal: [String] = []
        for (index, entry) in work.enumerated() {
            guard case .repo(let repo) = entry else { continue }
            if index < boundary { pinned.append(repo.id) } else { normal.append(repo.id) }
        }
        // A collapsed group's rows are absent from `entries`; re-attach them so a
        // move never drops them. Anything dragged into a collapsed zone joins it.
        if pinnedCollapsed {
            pinned = store.repos.filter { $0.pinned }.map { $0.id } + pinned
        }
        if listCollapsed {
            normal = store.repos.filter { !$0.pinned }.map { $0.id } + normal
        }
        store.applyRepoOrder(pinned: pinned, normal: normal)
    }
}

// MARK: - Grouping types

private enum RepoGroup {
    case pinned
    case list
}

private enum RepoEntry: Identifiable {
    case header(RepoGroup)
    case repo(TrackedRepo)

    var id: String {
        switch self {
        case .header(let group): return group == .pinned ? "__header_pinned" : "__header_list"
        case .repo(let repo): return "repo_\(repo.id)"
        }
    }
}

/// A tappable grey caption that collapses / expands its group.
private struct RepoGroupHeader: View {
    let group: RepoGroup
    let collapsed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(Localization.L(group == .pinned ? "pinnedRepos" : "repoList"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Strip the List's default row chrome and match the column's own spacing.
private struct PlainListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// A single tracked repository row.
/// Selected → deeper gray rounded rect; unselected → light gray (same as column
/// background) but the box stays visible via a faint border. Content is inset so
/// it never touches the box edge.
struct RepoRow: View {
    let repo: TrackedRepo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.textMuted, lineWidth: 1)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary)
                )
            Text("\(repo.owner)/\(repo.name)")
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(10)   // inward space that holds no content
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Theme.repoRowSelected : Theme.repoRowNormal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Color.clear : Theme.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

/// The "+" add button, sized like the other list rows.
struct RepoAddRow: View {
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.accentBlue)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.repoRowNormal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}