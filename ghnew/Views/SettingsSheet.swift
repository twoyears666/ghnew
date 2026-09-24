import SwiftUI

/// In-app settings: dark mode toggle, language picker, support links and a
/// red reset button that wipes all tracked data.
struct SettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section(Localization.L("appearance")) {
                    Toggle(Localization.L("darkMode"), isOn: $settings.isDarkMode)
                    Picker(Localization.L("language"), selection: $settings.language) {
                        ForEach(AppSettings.Language.allCases, id: \.self) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                }

                Section(Localization.L("support")) {
                    Button {
                        openExternal("https://github.com/twoyears666/ghnew/issues/new")
                    } label: {
                        row(icon: "ant.circle.fill", title: Localization.L("openIssue"))
                    }
                    .buttonStyle(.plain)
                    Button {
                        openExternal("https://github.com/twoyears666/ghnew")
                    } label: {
                        row(icon: "chevron.left.forwardslash.chevron.right", title: Localization.L("ghnewRepo"))
                    }
                    .buttonStyle(.plain)
                }

                Section(Localization.L("dangerZone")) {
                    Button(role: .destructive) { confirmReset = true } label: {
                        HStack {
                            Spacer()
                            Text(Localization.L("reset")).fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(Localization.L("settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Localization.L("done")) { dismiss() }
                }
            }
            .alert(Localization.L("reset"), isPresented: $confirmReset) {
                Button(Localization.L("reset"), role: .destructive) {
                    store.resetAll()
                    dismiss()
                }
                Button(Localization.L("cancel"), role: .cancel) {}
            } message: {
                Text(Localization.L("resetPrompt"))
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func row(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(Theme.accentBlue)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
        }
        .contentShape(Rectangle())
    }
}