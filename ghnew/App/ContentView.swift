import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: AppSettings

    private enum Level {
        case left     // repo list
        case middle   // messages of the selected repo
        case right    // detail of the selected message
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= geo.size.height {
                landscapeBody(width: geo.size.width)
            } else {
                portraitBody
            }
        }
        .sheet(isPresented: $store.showAddRepo) {
            AddRepoSheet()
                .environmentObject(store)
        }
        .alert("Error",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    /// Wide (landscape) layout: all three columns side by side.
    private func landscapeBody(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            LeftColumn()
                .frame(width: width * 0.24)
            MiddleColumn()
                .frame(maxWidth: .infinity)
            RightColumn()
                .frame(width: width * 0.20)
        }
        .background(Theme.pageBackground)
    }

    /// Narrow (portrait) layout: one column per screen so they don't get squished.
    /// Left → tap a repo → Middle → tap a message → Right; a back button walks back up.
    private var portraitBody: some View {
        let level = currentLevel
        return VStack(spacing: 0) {
            if level != .left {
                HStack(spacing: 12) {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Theme.columnBackground)
            }
            levelView(level)
        }
        .background(Theme.pageBackground)
    }

    private var currentLevel: Level {
        if store.selectedRepoID == nil { return .left }
        if let msg = store.selectedMessage, msg.repoID == store.selectedRepoID {
            return .right
        }
        return .middle
    }

    @ViewBuilder
    private func levelView(_ level: Level) -> some View {
        switch level {
        case .left:   LeftColumn()
        case .middle: MiddleColumn()
        case .right:  RightColumn()
        }
    }

    /// Right → middle clears the message only; middle → left clears the repo too.
    private func goBack() {
        if store.selectedMessageID != nil {
            store.selectedMessageID = nil
        } else {
            store.selectedMessageID = nil
            store.selectedRepoID = nil
        }
    }
}