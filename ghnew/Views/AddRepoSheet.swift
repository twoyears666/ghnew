import SwiftUI

/// Sheet to add a tracked repository with release/action notification toggles.
struct AddRepoSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var repoInput = ""
    @State private var watchRelease = true
    @State private var watchAction = true
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository") {
                    TextField("owner / repository", text: $repoInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Notifications") {
                    Toggle("Track releases", isOn: $watchRelease)
                    Toggle("Track actions", isOn: $watchAction)
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundColor(Theme.failRed)
                    }
                }
                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text("Add") }
                            Spacer()
                        }
                    }
                    .disabled(working)
                }
            }
            .navigationTitle("Add repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        errorText = nil
        let parts = repoInput.split(separator: "/", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            errorText = "Enter as owner / repository (e.g. twoyears666/ghnew)"
            return
        }
        working = true
        Task { @MainActor in
            do {
                try await store.addRepo(owner: parts[0], name: parts[1],
                                        watchRelease: watchRelease, watchAction: watchAction)
                dismiss()
            } catch {
                errorText = error.localizedDescription
                working = false
            }
        }
    }
}