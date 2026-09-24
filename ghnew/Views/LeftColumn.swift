import SwiftUI

/// Left column: app title + tracked repo list + add button.
struct LeftColumn: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ghnew")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.repos) { repo in
                        RepoRow(repo: repo,
                                isSelected: store.selectedRepoID == repo.id)
                            .onTapGesture { store.select(repo.id) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    if let idx = store.repos.firstIndex(where: { $0.id == repo.id }) {
                                        store.removeRepo(at: IndexSet(integer: idx))
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                    RepoAddRow()
                        .onTapGesture { store.showAddRepo = true }
                }
                .padding(6)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            Divider()
            LoginFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.columnBackground)
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