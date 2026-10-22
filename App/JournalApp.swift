import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Keyboard shortcuts of the app, one table for the menu bar, the quick-entry box and tests.
/// The menu items are Mac-only; ⌘⇧T in the quick-entry box also works on iPad (hardware keyboard).
enum JournalShortcut: CaseIterable {
    case search
    case quickSwitch
    case today
    case switchMode

    var key: KeyEquivalent {
        switch self {
        case .search: "f"
        case .quickSwitch: "k"
        case .today, .switchMode: "t"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        #if os(iOS)
            case .search: [.command, .shift]
        #endif
        case .switchMode: [.command, .shift]
        default: .command
        }
    }
}

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

    #if os(iOS)
        @State private var widgetSnapshots: WidgetSnapshotWriter
        @State private var widgetLinks: WidgetLinkHandler
        @State private var shareQueue: ShareQueueProcessor
    #endif

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
        #if os(iOS)
            let widgetSnapshots = WidgetSnapshotWriter(
                store: store, group: SystemAppGroupStore(), isLocked: { IntentActions.shared.isLocked() },
                lockDeadline: { [weak appLock] in appLock?.locksAt })
            if AppLaunchPolicy.allowsAutomaticStart() { widgetSnapshots.attach() }
            _widgetSnapshots = State(initialValue: widgetSnapshots)
            _widgetLinks = State(
                initialValue: WidgetLinkHandler(actions: IntentActions.shared, navigation: IntentNavigation.shared))
            _shareQueue = State(
                initialValue: ShareQueueProcessor(
                    store: store, group: SystemAppGroupStore(), isLocked: { IntentActions.shared.isLocked() },
                    appLockEnabled: { appLock.isEnabled }))
        #endif
        #if os(macOS)
            _desktop = State(initialValue: MacQuickEntryController(store: store, location: location, appLock: appLock))
        #endif
    }

    var body: some Scene {
        #if os(macOS)
            mainWindow.commands {
                CommandGroup(after: .textEditing) {
                    Button("Ara") { openSearch?() }
                        .keyboardShortcut(
                            JournalShortcut.search.key, modifiers: JournalShortcut.search.modifiers
                        )
                        .disabled(openSearch == nil || appLock.shouldCover)
                    Button("Hızlı geçiş") { openSearch?() }
                        .keyboardShortcut(
                            JournalShortcut.quickSwitch.key,
                            modifiers: JournalShortcut.quickSwitch.modifiers
                        )
                        .disabled(openSearch == nil || appLock.shouldCover)
                }
                CommandMenu("Git") {
                    Button("Bugüne git") { goToToday?() }
                        .keyboardShortcut(JournalShortcut.today.key, modifiers: JournalShortcut.today.modifiers)
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
                MacSettingsView(store: store, shortcut: desktop.shortcut)
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
                #if os(iOS)
                    // What the share extension added or queued, once the app has taken it in.
                    .safeAreaInset(edge: .top, spacing: 0) { ShareImportBand(processor: shareQueue) }
                #endif
                .appLockShield(appLock)
                #if os(macOS)
                    .background(MainWindowMarker())
                    .task { await desktop.start() }
                #else
                    // A tap in the home-screen widget opens the app with a widget link.
                    .onOpenURL { url in Task { await widgetLinks.open(url) } }
                    // The unlock writes the widget snapshot once; while locked nothing touches it.
                    .onChange(of: appLock.isLocked) { _, locked in
                        guard !locked, AppLaunchPolicy.allowsAutomaticStart() else { return }
                        widgetSnapshots.update()
                        Task { await widgetLinks.unlocked() }
                        shareQueue.process()
                    }
                    // The share extension learns where the vault is; texts it queued enter once
                    // the vault is open (docs/architecture.md, "Paylaşım uzantısı").
                    .onChange(of: store.lastUpdated != nil) { _, published in
                        guard published, AppLaunchPolicy.allowsAutomaticStart() else { return }
                        shareQueue.publishTarget()
                        shareQueue.process()
                    }
                    .onChange(of: appLock.isEnabled) {
                        if AppLaunchPolicy.allowsAutomaticStart() { shareQueue.publishTarget() }
                    }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            #if os(iOS)
                if AppLaunchPolicy.allowsAutomaticStart() {
                    // Leaving goes through the widget writer: the lock and the snapshot move together.
                    switch phase {
                    case .active: appLock.activate()
                    case .inactive: widgetSnapshots.sceneLeftForeground(lockService: appLock, background: false)
                    case .background: widgetSnapshots.sceneLeftForeground(lockService: appLock, background: true)
                    @unknown default: widgetSnapshots.sceneLeftForeground(lockService: appLock, background: true)
                    }
                }
            #endif
            if phase == .active && AppLaunchPolicy.allowsAutomaticStart() {
                #if os(iOS)
                    // A new day, or a vault changed while away; a locked app leaves the snapshot alone.
                    widgetSnapshots.update()
                    shareQueue.publishTarget()
                    shareQueue.process()
                #endif
                Task {
                    location.refreshAuthorization()
                    await calendar.refresh()
                    await notifications.foreground()
                }
            }
            if phase == .background && AppLaunchPolicy.allowsAutomaticStart() {
                Task { await notifications.replanNow() }
                #if os(iOS)
                    shareQueue.publishTarget()
                #endif
            }
            #if os(macOS)
                store.setForeground(phase == .active || desktop.window.isPresented)
            #else
                store.setForeground(phase == .active)
            #endif
        }
    }
}

#if os(iOS)
    /// "1 paylaşım eklendi" and the like, after the app took in what the share extension left.
    private struct ShareImportBand: View {
        let processor: ShareQueueProcessor

        var body: some View {
            if let report = processor.report {
                InfoBand(
                    kind: report.unreadable + report.waiting > 0 ? .warning : .info, verbatim: report.message,
                    onDismiss: processor.dismissReport
                )
                .background(Color.ink.paper)
                .accessibilityIdentifier("banner.shareImport")
            }
        }
    }
#endif
