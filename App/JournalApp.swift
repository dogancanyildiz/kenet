import SwiftUI

@main
struct JournalApp: App {
    @State private var store = IndexStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.setForeground(phase == .active)
        }
    }
}
