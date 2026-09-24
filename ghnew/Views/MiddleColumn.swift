import SwiftUI

/// Middle column: header with the selected repo name + message card list.
struct MiddleColumn: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(store.selectedRepo?.id ?? "Messages")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                HStack(spacing: 12) {
                    if let repo = store.selectedRepo,
                       let url = URL(string: "https://github.com/\(repo.owner)/\(repo.name)") {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(Theme.accentBlue)
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 4) {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text("Refresh")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Theme.accentBlue)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await store.refreshAll() }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Theme.cardBorder)
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            if store.messagesForSelected.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.textMuted)
                    Text("No releases or actions yet.\nPull to refresh or press Refresh.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.messagesForSelected) { msg in
                            if msg.kind == .release {
                                ReleaseCard(message: msg)
                            } else {
                                ActionCard(message: msg)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .refreshable { await store.refreshAll() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.pageBackground)
    }
}