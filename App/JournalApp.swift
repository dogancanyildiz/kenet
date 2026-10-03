import SwiftUI

@main
struct JournalApp: App {
    @State private var store = IndexStore()
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
        @FocusedValue(\.goToToday) private var goToToday
    #endif

    var body: some Scene {
        #if os(macOS)
            mainWindow.commands {
                CommandMenu("Git") {
                    Button("Bugüne git") { goToToday?() }
                        .keyboardShortcut("t", modifiers: .command)
                        .disabled(goToToday == nil)
                }
            }
            Settings {
                DiagnosticsView(store: store)
                    .frame(minWidth: 450, minHeight: 500)
            }
        #else
            mainWindow
        #endif
    }

    private var mainWindow: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.setForeground(phase == .active)
        }
    }
}
