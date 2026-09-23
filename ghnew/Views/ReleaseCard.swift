import SwiftUI

/// A release card: version title, hollow colored pill, then the rendered changelog.
struct ReleaseCard: View {
    let message: GHMessage

    private var title: String {
        message.releaseTitle ?? "Release"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                PillBadge(text: message.releaseBadge,
                          color: message.isReleaseBadgeGreen ? Theme.releaseGreen : Theme.prereleaseBrown)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                    Text("open")
                        .font(.system(size: 11))
                }
                .foregroundColor(Theme.textMuted)
            }

            if let body = message.releaseBody?.nilIfEmpty, !body.isEmpty {
                MarkdownView(markdown: body, fontSize: 13)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghCard()
        .contentShape(Rectangle())
        .onTapGesture {
            openExternal(message.releaseURL)
        }
    }
}