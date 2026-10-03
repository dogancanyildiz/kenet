import SwiftUI

@main
struct JournalApp: App {
    @State private var store: IndexStore
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
        @State private var desktop: MacQuickEntryController
        @FocusedValue(\.goToToday) private var goToToday
        @FocusedValue(\.openSearch) private var openSearch
    #endif

    init() {
        let store = IndexStore()
        _store = State(initialValue: store)
        #if os(macOS)
            _desktop = State(initialValue: MacQuickEntryController(store: store))
        #endif
    }

    var body: some Scene {
        #if os(macOS)
            mainWindow.commands {
                CommandGroup(after: .textEditing) {
                    Button("Ara") { openSearch?() }
                        .keyboardShortcut("f", modifiers: .command)
                        .disabled(openSearch == nil)
                    Button("Hızlı geçiş") { openSearch?() }
                        .keyboardShortcut("k", modifiers: .command)
                        .disabled(openSearch == nil)
                }
                CommandMenu("Git") {
                    Button("Bugüne git") { goToToday?() }
                        .keyboardShortcut("t", modifiers: .command)
                        .disabled(goToToday == nil)
                }
            }
            MenuBarExtra {
                MacQuickEntryMenu(controller: desktop)
            } label: {
                Label("Hızlı giriş", systemImage: "square.and.pencil")
                    .task { await desktop.start() }
            }
            Settings {
                TabView {
                    HotKeySettingsView(model: desktop.shortcut)
                        .tabItem { Label("Hızlı giriş", systemImage: "square.and.pencil") }
                    DiagnosticsView(store: store)
                        .tabItem { Label("Kasa", systemImage: "folder") }
                }
                .frame(minWidth: 450, minHeight: 500)
            }
        #else
            mainWindow
        #endif
    }

    private var mainWindow: some Scene {
        WindowGroup(id: "main") {
            ContentView(store: store)
                #if os(macOS)
                    .background(MainWindowMarker())
                    .task { await desktop.start() }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            #if os(macOS)
                store.setForeground(phase == .active || desktop.window.isPresented)
            #else
                store.setForeground(phase == .active)
            #endif
        }
    }
}
