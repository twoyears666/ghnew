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
/// logged out). Tapping opens a GitHub web popup (logged in) or the login sheet
/// (logged out). Long-press to sign out.
struct LoginFooter: View {
    @EnvironmentObject var store: AppStore
    @State private var showLogin = false
    @State private var showWeb = false

    private var avatarURL: URL? {
        guard let s = store.currentUser?.avatar_url, let u = URL(string: s) else { return nil }
        return u
    }

    private var profileURL: URL {
        guard let login = store.currentUser?.login, !login.isEmpty else {
            return URL(string: "https://github.com")!
        }
        return URL(string: "https://github.com/\(login)")!
    }

    var body: some View {
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
                    // Person silhouette (circle + cut half-circle) when logged out.
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Text(store.isLoggedIn ? (store.currentUser?.login ?? "登录") : "登录")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture {
            if store.isLoggedIn { showWeb = true } else { showLogin = true }
        }
        .contextMenu {
            if store.isLoggedIn {
                Button(role: .destructive) {
                    store.logout()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .sheet(isPresented: $showLogin) { LoginSheet().environmentObject(store) }
        .fullScreenCover(isPresented: $showWeb) {
            SafariWebView(url: profileURL).ignoresSafeArea()
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