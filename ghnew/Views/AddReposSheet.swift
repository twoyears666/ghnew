import SwiftUI

/// First-login flow: shows the authenticated account's repositories with a
/// checkbox to pick which to track. Presented right after a successful login.
struct AddReposSheet: View {
    @EnvironmentObject var store: AppStore

    @State private var repos: [GHRepoListItem] = []
    @State private var selected: Set<Int> = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if repos.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 26))
                            .foregroundColor(Theme.textMuted)
                        Text(Localization.L("noRepos"))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(repos) { repo in
                        Button { toggle(repo.id) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected.contains(repo.id) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 17))
                                    .foregroundColor(selected.contains(repo.id) ? Theme.accentBlue : Theme.textMuted)
                                Text(repo.full_name)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(Localization.L("addRepos"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Localization.L("addSelected")) { Task { await addSelected() } }
                        .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localization.L("skip")) {
                        store.showRepoPicker = false
                    }
                }
            }
        }
        .task {
            let items = (try? await GitHubAPI.shared.fetchUserRepos()) ?? []
            repos = items
            loading = false
        }
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func addSelected() async {
        for repo in repos where selected.contains(repo.id) {
            let key = repo.full_name.lowercased()
            guard !store.repos.contains(where: { $0.id.lowercased() == key }) else { continue }
            try? await store.addRepo(owner: repo.ownerLogin, name: repo.repoName,
                                     watchRelease: true, watchAction: true, notify: true)
        }
        store.showRepoPicker = false
    }
}