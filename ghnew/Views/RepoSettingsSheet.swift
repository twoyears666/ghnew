import SwiftUI

/// Edit tracking options for an already-added repository (opened via a
/// long-press on the repo row).
struct RepoSettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let repo: TrackedRepo
    @State private var watchRelease: Bool
    @State private var watchAction: Bool
    @State private var notify: Bool

    init(repo: TrackedRepo) {
        self.repo = repo
        _watchRelease = State(initialValue: repo.watchRelease)
        _watchAction = State(initialValue: repo.watchAction)
        _notify = State(initialValue: repo.notify)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Localization.L("repository")) {
                    Text(repo.id)
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                }
                Section(Localization.L("notifications")) {
                    Toggle(Localization.L("trackReleases"), isOn: $watchRelease)
                    Toggle(Localization.L("trackActions"), isOn: $watchAction)
                    Toggle(Localization.L("sendNotifications"), isOn: $notify)
                }
                Section {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text(Localization.L("save")).fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(Localization.L("repoSettings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localization.L("cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        var r = repo
        r.watchRelease = watchRelease
        r.watchAction = watchAction
        r.notify = notify
        store.updateRepo(r)
    }
}