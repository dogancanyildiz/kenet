import SwiftUI

#if os(macOS)
    import AppKit
#endif

@main
struct JournalApp: App {
    @State private var intentNavigation = IntentNavigation.shared
    @State private var geofences: GeofenceService
    @State private var location: LocationService
    @State private var calendar = CalendarService()
    @State private var notifications: NotificationService
    @State private var store: IndexStore
    @State private var appLock: AppLockService
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
        @State private var desktop: MacQuickEntryController
        @FocusedValue(\.goToToday) private var goToToday
        @FocusedValue(\.openSearch) private var openSearch
    #endif

    init() {
        let appLock = AppLockService()
        _appLock = State(initialValue: appLock)
        let location = LocationService()
        _location = State(initialValue: location)
        let store = IntentActions.shared.store
        IntentActions.shared.attach(lock: appLock)
        _store = State(initialValue: store)
        let center = SystemNotificationScheduler()
        let geofences = GeofenceService(location: location, center: center)
        geofences.attach(to: store)
        geofences.attach(lock: appLock)
        _geofences = State(initialValue: geofences)
        let notifications = NotificationService(center: center)
        notifications.attach(to: store)
        notifications.activateAutomatically()
        _notifications = State(initialValue: notifications)
        geofences.onLockedMarkBlocked = { [weak notifications] in
            notifications?.open(.goals)
        }
        IntentNavigation.shared.onOpenToday = { [weak notifications] in notifications?.clearNavigationRequest() }
        geofences.activateAutomatically()
        #if os(macOS)
            _desktop = State(initialValue: MacQuickEntryController(store: store, location: location, appLock: appLock))
        #endif
    }

    var body: some Scene {
        #if os(macOS)
            mainWindow.commands {
                CommandGroup(after: .textEditing) {
                    Button("Ara") { openSearch?() }
                        .keyboardShortcut("f", modifiers: .command)
                        .disabled(openSearch == nil || appLock.shouldCover)
                    Button("Hızlı geçiş") { openSearch?() }
                        .keyboardShortcut("k", modifiers: .command)
                        .disabled(openSearch == nil || appLock.shouldCover)
                }
                CommandMenu("Git") {
                    Button("Bugüne git") { goToToday?() }
                        .keyboardShortcut("t", modifiers: .command)
                        .disabled(goToToday == nil || appLock.shouldCover)
                }
            }
            MenuBarExtra {
                MacQuickEntryMenu(controller: desktop)
            } label: {
                Label("Hızlı giriş", systemImage: "square.and.pencil")
                    .task { await desktop.start() }
                    .onChange(of: intentNavigation.todayRequest, initial: true) { _, request in
                        if request != nil {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "main")
                        }
                    }
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
                .environment(geofences)
                .environment(notifications)
                .environment(intentNavigation)
                .environment(appLock)
                .appLockShield(appLock)
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
                .environment(geofences)
                .environment(notifications)
                .environment(intentNavigation)
                .environment(appLock)
                .appLockShield(appLock)
                #if os(macOS)
                    .background(MainWindowMarker())
                    .task { await desktop.start() }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            #if os(iOS)
                if AppLaunchPolicy.allowsAutomaticStart() {
                    switch phase {
                    case .active: appLock.activate()
                    case .inactive: appLock.resignActive(startTimeout: false)
                    case .background: appLock.resignActive(startTimeout: true)
                    @unknown default: appLock.resignActive(startTimeout: true)
                    }
                }
            #endif
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
