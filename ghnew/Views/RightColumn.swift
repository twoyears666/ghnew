import SwiftUI

/// Right column — intentionally empty for now (future work).
struct RightColumn: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.columnBackground)
    }
}