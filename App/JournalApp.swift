import SwiftUI

#if os(macOS)
    import AppKit
#endif

@main
struct JournalApp: App {
    @State private var location: LocationService
    @State private var calendar = CalendarService()
    @State private var notifications: NotificationService
    @State private var store: IndexStore
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
        @State private var desktop: MacQuickEntryController
        @FocusedValue(\.goToToday) private var goToToday
        @FocusedValue(\.openSearch) private var openSearch
    #endif

    init() {
        let location = LocationService()
        _location = State(initialValue: location)
        let store = IndexStore()
        _store = State(initialValue: store)
        let notifications = NotificationService()
        notifications.attach(to: store)
        notifications.activateAutomatically()
        _notifications = State(initialValue: notifications)
        #if os(macOS)
            _desktop = State(initialValue: MacQuickEntryController(store: store, location: location))
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
                    .onChange(of: notifications.navigationRequest?.id, initial: true) { _, request in
                        if request != nil {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "main")
                        }
                    }
            }
            Settings {
                TabView {
                    HotKeySettingsView(model: desktop.shortcut)
                        .tabItem { Label("Hızlı giriş", systemImage: "square.and.pencil") }
                    NavigationStack { NotificationSettingsView() }
                        .tabItem { Label("Bildirimler", systemImage: "bell") }
                    DiagnosticsView(store: store)
                        .tabItem { Label("Kasa", systemImage: "folder") }
                }
                .frame(minWidth: 450, minHeight: 500)
                .environment(calendar)
                .environment(location)
                .environment(notifications)
            }
        #else
            mainWindow
        #endif
    }

    private var mainWindow: some Scene {
        WindowGroup(id: "main") {
            ContentView(store: store)
                .environment(calendar)
                .environment(location)
                .environment(notifications)
                #if os(macOS)
                    .background(MainWindowMarker())
                    .task { await desktop.start() }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active && AppLaunchPolicy.allowsAutomaticStart() {
                Task {
                    location.refreshAuthorization()
                    await calendar.refresh()
                    await notifications.foreground()
                }
            }
            if phase == .background && AppLaunchPolicy.allowsAutomaticStart() {
                Task { await notifications.replanNow() }
            }
            #if os(macOS)
                store.setForeground(phase == .active || desktop.window.isPresented)
            #else
                store.setForeground(phase == .active)
            #endif
        }
    }
}
