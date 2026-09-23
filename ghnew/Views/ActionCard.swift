import SwiftUI

/// An action (workflow run) card.
struct ActionCard: View {
    let message: GHMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: title (wraps) + status icon pinned to the right.
            HStack(alignment: .top, spacing: 10) {
                Text(message.actionTitle?.nilIfEmpty ?? "Workflow run")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 18)
                RunStatusView(message: message)
            }

            // "development build #12: commit 1522b17 pushed by identity"
            summaryLine
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)

            // Calendar + relative trigger time.
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                Text(TimeFormat.relative(message.createdAt))
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .foregroundColor(Theme.textSecondary)

            // Stopwatch + duration + branch badge.
            HStack(spacing: 6) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 11))
                Text(TimeFormat.duration(message.duration ?? 0))
                    .font(.system(size: 12))
                BranchBadge(name: message.branch)
                Spacer(minLength: 0)
            }
            .foregroundColor(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghCard()
        .contentShape(Rectangle())
        .onTapGesture {
            openExternal(message.actionsURL)
        }
    }

    private var summaryLine: Text {
        Text("development build").bold().underline()
        + Text("  #\(message.runNumber ?? 0): commit ")
        + Text(message.commitID ?? "").underline()
        + Text(" pushed by ")
        + Text(message.actor ?? "").underline()
    }
}