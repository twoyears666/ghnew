import SwiftUI

/// The two acceleration panes.
enum AccelTab: String, CaseIterable, Identifiable {
    case relay
    case concurrency

    var id: String { rawValue }
    var title: String { self == .relay ? Localization.L("relayTab") : Localization.L("concTab") }
    var icon: String { self == .relay ? "network" : "bolt.fill" }
}

/// Standalone "加速" page. Portrait keeps the tab directory in a bottom bar;
/// landscape mirrors the main three-column layout with the directory on the
/// left and a merged (former middle + right) content pane.
struct AccelerationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var tab: AccelTab = .relay

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width >= geo.size.height {
                    landscape(width: geo.size.width)
                } else {
                    portrait
                }
            }
        }
        .background(Theme.pageBackground)
    }

    // MARK: - Portrait

    private var portrait: some View {
        VStack(spacing: 0) {
            header(title: Localization.L("accelerate"))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle()
                .fill(Theme.cardBorder)
                .frame(height: 1)
            // Only two entries — always fits, so no scrolling strip.
            HStack(spacing: 8) {
                ForEach(AccelTab.allCases) { t in
                    AccelTabButton(tab: t, selected: tab == t, expanded: true) { tab = t }
                }
            }
            .padding(8)
            .background(Theme.columnBackground)
        }
    }

    // MARK: - Landscape

    private func landscape(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Localization.L("accelerate"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(AccelTab.allCases) { t in
                            AccelTabButton(tab: t, selected: tab == t, expanded: false) { tab = t }
                        }
                    }
                    .padding(6)
                }
                Spacer(minLength: 0)
            }
            .frame(width: width * 0.24)
            .background(Theme.columnBackground)

            VStack(spacing: 0) {
                header(title: tab.title)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.pageBackground)
        }
    }

    // MARK: - Shared

    private func header(title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.columnBackground)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch tab {
                case .relay:       RelayTabView()
                case .concurrency: ConcurrencyTabView()
                }
            }
            .padding(14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Directory button styled like the tracked-repo rows.
private struct AccelTabButton: View {
    let tab: AccelTab
    let selected: Bool
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if expanded { Spacer(minLength: 0) }
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundColor(selected ? Theme.accentBlue : Theme.textSecondary)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: expanded ? .infinity : nil, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.repoRowSelected : Theme.repoRowNormal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.clear : Theme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// White card used across both panes.
@ViewBuilder
private func accelCard<Content: View>(padding: CGFloat = 12,
                                      @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) { content() }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghCard()
}

private func accelSectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(Theme.textSecondary)
        .textCase(.uppercase)
}

// MARK: - Relay pane

private struct RelayTabView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var latency: [String: Int] = [:]   // host -> ms, -1 = failed
    @State private var testing = false

    private struct LatencyResult: Sendable {
        let host: String
        let ms: Int?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            accelCard {
                Toggle(Localization.L("masterSwitch"), isOn: $settings.accelRelayEnabled)
                    .toggleStyle(.switch)
                    .tint(Theme.accentBlue)
            }

            accelSectionTitle(Localization.L("relayNodes"))

            accelCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(Accelerator.relayNodes.enumerated()), id: \.element.id) { index, node in
                        if index > 0 { Divider() }
                        nodeRow(node)
                    }
                }
            }

            Button(action: testAll) {
                HStack(spacing: 6) {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "speedometer").font(.system(size: 13))
                    }
                    Text(Localization.L("testLatency"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(Theme.accentBlue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(testing)

            accelCard {
                Toggle(Localization.L("includeArtifacts"), isOn: $settings.accelRelayIncludeArtifacts)
                    .toggleStyle(.switch)
                    .tint(Theme.accentBlue)
                Text(Localization.L("artifactRiskWarn"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.prereleaseBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(Localization.L("relayHint"))
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nodeRow(_ node: RelayNode) -> some View {
        let chosen = settings.accelRelayNode == node.host
        return Button {
            settings.accelRelayNode = node.host
        } label: {
            HStack(spacing: 10) {
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(chosen ? Theme.accentBlue : Theme.textMuted)
                    .frame(width: 20)
                Text(node.host)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                latencyBadge(node.host)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func latencyBadge(_ host: String) -> some View {
        if let ms = latency[host] {
            let grade = Accelerator.grade(ms < 0 ? nil : ms)
            PillBadge(text: ms < 0 ? grade.label : "\(ms)ms · \(grade.label)",
                      color: color(for: grade))
        } else {
            Text("-")
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
        }
    }

    private func color(for grade: LatencyGrade) -> Color {
        switch grade {
        case .fast:            return Theme.successGreen
        case .medium:          return Theme.prereleaseBrown
        case .slow, .failed:   return Theme.failRed
        }
    }

    private func testAll() {
        testing = true
        Task {
            await withTaskGroup(of: LatencyResult.self) { group in
                for node in Accelerator.relayNodes {
                    group.addTask {
                        LatencyResult(host: node.host, ms: await Accelerator.measureLatency(host: node.host))
                    }
                }
                for await result in group {
                    await MainActor.run { latency[result.host] = result.ms ?? -1 }
                }
            }
            await MainActor.run { testing = false }
        }
    }
}

// MARK: - Concurrency pane

private struct ConcurrencyTabView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let levels = [2, 4, 8]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            accelCard {
                Toggle(Localization.L("masterSwitch"), isOn: $settings.accelConcurrencyEnabled)
                    .toggleStyle(.switch)
                    .tint(Theme.accentBlue)
            }

            accelCard {
                accelSectionTitle(Localization.L("concLevel"))
                Picker(Localization.L("concLevel"), selection: $settings.accelConcurrencyLevel) {
                    ForEach(levels, id: \.self) { level in
                        Text("\(level)").tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            accelCard {
                Toggle(Localization.L("includeArtifacts"), isOn: $settings.accelConcurrencyIncludeArtifacts)
                    .toggleStyle(.switch)
                    .tint(Theme.accentBlue)
                Text(Localization.L("artifactRiskWarn"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.prereleaseBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(Localization.L("concHint"))
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}