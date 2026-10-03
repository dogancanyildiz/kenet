import SwiftUI

/// Starts the vault once and presents the platform's phase-one navigation.
struct ContentView: View {
    let store: IndexStore

    var body: some View {
        Group {
            #if os(macOS)
                MacNavigation(store: store)
            #else
                PhoneNavigation(store: store)
            #endif
        }
        .task { await store.startAutomatically() }
    }
}
