import SwiftUI
import UserNotifications

@main
struct ghnewApp: App {
    @StateObject private var store = AppStore()
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .preferredColorScheme(settings.isDarkMode ? .dark : .light)
                .onAppear {
                    requestNotificationPermission()
                }
                .onOpenURL { url in
                    handle(url: url)
                }
        }
    }

    @MainActor
    private func handle(url: URL) {
        guard url.scheme == "ghnew" else { return }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        guard let host = comps.host else { return }
        let parts = comps.path.split(separator: "/").map(String.init)
        switch host {
        case "add":
            if parts.count >= 2 {
                store.prefillAddRepo(owner: parts[0], name: parts[1])
            }
        case "repo":
            if parts.count >= 2 {
                store.openRepo(parts[0], parts[1])
            }
        case "release":
            if parts.count >= 3 {
                Task { await store.openRelease(owner: parts[0], name: parts[1], tag: parts[2]) }
            }
        case "action":
            if parts.count >= 3, let runID = Int(parts[2]) {
                Task { await store.openAction(owner: parts[0], name: parts[1], runID: runID) }
            }
        default:
            break
        }
    }
}

private func requestNotificationPermission() {
    UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
}