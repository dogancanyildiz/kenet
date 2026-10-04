import SwiftUI

/// Starts the vault once and presents the platform's phase-one navigation.
struct ContentView: View {
    let store: IndexStore
    @Environment(IntentNavigation.self) private var intentNavigation
    @Environment(NotificationService.self) private var notifications
    @State private var searchPresented = false

    var body: some View {
        Group {
            #if os(macOS)
                MacNavigation(store: store)
            #else
                PhoneNavigation(store: store)
            #endif
        }
        .environment(\.openSearch, { searchPresented = true })
        .sheet(isPresented: $searchPresented) {
            SearchView(store: store)
                .environment(\.openSearch, { searchPresented = true })
        }
        #if os(macOS)
            .focusedSceneValue(\.openSearch, { searchPresented = true })
        #endif
        .onChange(of: intentNavigation.todayRequest) { searchPresented = false }
        .onChange(of: notifications.navigationRequest?.id) { _, _ in searchPresented = false }
        .task { await store.startAutomatically() }
    }
}
