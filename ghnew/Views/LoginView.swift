import SwiftUI
import SafariServices

/// Wrapper around SFSafariViewController used for the GitHub web "popup".
struct SafariWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// Bottom of the left column: circular avatar + bold username (or "登录" when
/// logged out), trailing gear button that opens settings. Tapping the account
/// opens the login sheet (logged out) or a two-step sign-out flow (logged in).
/// After a fresh login the first-login repo picker appears.
struct LoginFooter: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: AppSettings
    @State private var showLogin = false
    @State private var showSettings = false
    @State private var showSignOutPrompt = false
    @State private var showSignOutConfirm = false

    private var avatarURL: URL? {
        guard let s = store.currentUser?.avatar_url, let u = URL(string: s) else { return nil }
        return u
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.repoRowSelected)
                        .frame(width: 36, height: 36)
                    if store.isLoggedIn {
                        AsyncImage(url: avatarURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                Text(store.isLoggedIn ? (store.currentUser?.login ?? Localization.L("login")) : Localization.L("login"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture {
                if store.isLoggedIn {
                    showSignOutPrompt = true
                } else {
                    showLogin = true
                }
            }
        }
        .sheet(isPresented: $showLogin) { LoginSheet().environmentObject(store) }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(store) }
        .sheet(isPresented: $store.showRepoPicker) { AddReposSheet().environmentObject(store) }
        .confirmationDialog(Localization.L("signOutTitle"), isPresented: $showSignOutPrompt, titleVisibility: .visible) {
            Button(Localization.L("logOut"), role: .destructive) {
                showSignOutPrompt = false
                showSignOutConfirm = true
            }
            Button(Localization.L("cancel"), role: .cancel) {}
        }
        .alert(Localization.L("signOutTitle"), isPresented: $showSignOutConfirm) {
            Button(Localization.L("logOut"), role: .destructive) {
                store.logout()
            }
            Button(Localization.L("cancel"), role: .cancel) {}
        } message: {
            Text(Localization.L("signOutConfirm"))
        }
    }
}

/// Login panel: create a token on GitHub (web popup) then paste it here.
struct LoginSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var working = false
    @State private var errorText: String?
    @State private var showTokenWeb = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Log in with a GitHub personal access token. It is stored on this device and used for GitHub API requests.")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                }
                Section("Token") {
                    SecureField("ghp_...", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        showTokenWeb = true
                    } label: {
                        Label("Create token on GitHub", systemImage: "safari")
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundColor(Theme.failRed)
                    }
                }
                Section {
                    Button(action: login) {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text("Login") }
                            Spacer()
                        }
                    }
                    .disabled(working || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Log in to GitHub")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .fullScreenCover(isPresented: $showTokenWeb) {
            SafariWebView(url: URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=ghnew&type=classic")!)
                .ignoresSafeArea()
        }
    }

    private func login() {
        working = true
        errorText = nil
        Task { @MainActor in
            do {
                try await store.login(token: token)
                dismiss()
            } catch {
                errorText = error.localizedDescription
                working = false
            }
        }
    }
}