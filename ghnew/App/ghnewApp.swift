import SwiftUI
import UserNotifications

@main
struct ghnewApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .onAppear {
                    requestNotificationPermission()
                }
        }
    }
}

private func requestNotificationPermission() {
    UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
}