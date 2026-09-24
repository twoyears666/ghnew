import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Card styling (white bg, light-blue-gray border, rounded, subtle shadow)

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
            .shadow(color: Theme.cardShadow, radius: 3, x: 0, y: 1)
    }
}

extension View {
    func ghCard() -> some View { modifier(CardStyle()) }
}

// MARK: - Hollow capsule pill

struct PillBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color, lineWidth: 1.2))
    }
}

// MARK: - Branch badge (light blue rounded rect, blue text)

struct BranchBadge: View {
    let name: String?

    var body: some View {
        if let name = name, !name.isEmpty {
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.branchBlueText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Theme.branchBlueBg))
        }
    }
}

// MARK: - Action run status icon (green check / red x / spinner)

struct RunStatusView: View {
    let message: GHMessage

    var body: some View {
        Group {
            if message.runStatus == "completed" {
                switch message.runConclusion {
                case "success":
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.successGreen)
                case "failure", "startup_failure":
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.failRed)
                case "cancelled", "timed_out", "action_required", "neutral", "skipped":
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textMuted)
                default:
                    Image(systemName: "circle")
                        .foregroundColor(Theme.textMuted)
                }
            } else if message.runStatus == "queued" || message.runStatus == "pending" {
                Image(systemName: "clock")
                    .foregroundColor(Theme.textSecondary)
            } else {
                // in_progress / waiting → spinner
                ProgressView()
            }
        }
        .font(.system(size: 22))
        .frame(width: 26, height: 26)
    }
}

// MARK: - URL helpers

func openExternal(_ urlString: String?) {
    guard let urlString = urlString, let url = URL(string: urlString) else { return }
    #if canImport(UIKit)
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    #else
    NSWorkspace.shared.open(url)
    #endif
}