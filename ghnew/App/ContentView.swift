import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                LeftColumn()
                    .frame(width: geo.size.width * 0.24)
                MiddleColumn()
                    .frame(maxWidth: .infinity)
                RightColumn()
                    .frame(width: geo.size.width * 0.20)
            }
            .background(Theme.pageBackground)
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
}