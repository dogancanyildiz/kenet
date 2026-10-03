import SwiftUI

/// Starts the vault once and presents the platform's phase-one navigation.
struct ContentView: View {
    let store: IndexStore
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
        .task { await store.startAutomatically() }
    }
}
