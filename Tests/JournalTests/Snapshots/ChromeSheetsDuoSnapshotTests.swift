#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    enum ChromeSheetsDuoCase: String, CaseIterable, Sendable {
        case today, selectedTask, settings, search, taskDetail, closeDay, quickEntry, kanbanPanel

        var isSheet: Bool {
            switch self {
            case .settings, .search, .taskDetail, .closeDay: true
            default: false
            }
        }

        /// Sheets that go through `inkAdaptiveSheetPresentation` / `inkAdaptiveFormPresentation`;
        /// search (`ContentView`) keeps the system sheet.
        var usesFormSizing: Bool { isSheet && self != .search }

        /// Hosted by the real `AdaptiveNavigation`, which sets the shell kind itself.
        var usesShell: Bool {
            switch self {
            case .today, .selectedTask, .settings: true
            default: false
            }
        }

        /// The shell cases carry the system's floating sidebar button (iOS 26 glass), whose blur
        /// differs from frame to frame; the capture paints that square over before comparing.
        var sidebarButtonMask: CGRect? {
            switch self {
            case .today, .selectedTask, .settings: CGRect(x: 0, y: 40, width: 100, height: 80)
            default: nil
            }
        }

        /// Search is hosted but not drawn: its system sheet (`ContentView`, no form sizing) moves
        /// with the simulator keyboard, so two runs differ. The hosted suite still checks its content.
        static let drawn = allCases.filter { $0 != .search }
    }

    /// Captures the window, including system form sheets, rather than only the presenting view.
    @MainActor
    @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DUO"] == "1"))
    struct ChromeSheetsDuoSnapshotTests {
        @Test(arguments: ChromeSheetsDuoCase.drawn)
        func chrome(_ screen: ChromeSheetsDuoCase) async throws {
            try await ChromeSheetsDuoHost.withWindow(screen) { window, host in
                if screen.isSheet {
                    let sheet = try #require(host.presentedViewController)
                    #expect(sheet.view.bounds.height >= 360)
                    if screen.usesFormSizing { #expect(sheet.view.bounds.width >= 480) }
                    #expect(
                        ChromeSheetsDuoHost.hasVisibleRowOrField(in: sheet.view),
                        "The presented sheet must contain a visible row or input.")
                }
                // The window is drawn here, not handed to the library: its view strategy parks a
                // view without a window inside one of its own, which corrupts a `UIWindow`.
                let format = UIGraphicsImageRendererFormat()
                format.scale = 2
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    if let mask = screen.sidebarButtonMask {
                        UIColor.gray.setFill()
                        UIRectFill(mask)
                    }
                }
                assertSnapshot(
                    of: image,
                    as: .image(precision: snapshotPrecision, perceptualPrecision: snapshotPerceptualPrecision),
                    named: screen.rawValue,
                    record: ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                        .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:)),
                    testName: "chrome")
            }
        }
    }

    @MainActor enum ChromeSheetsDuoHost {
        /// The previous case's window, released only once the next case has its own.
        private static var retired: UIWindow?

        static func withWindow(
            _ screen: ChromeSheetsDuoCase,
            body: @MainActor (UIWindow, UIHostingController<AnyView>) throws -> Void
        ) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let row = try #require(try await store.allTasks().first { !$0.isClosed })
            let defaults = context.defaults.defaults
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let navigation = ShellNavigationState()
            if screen == .selectedTask {
                navigation.section = .tasks
                navigation.selectedTask = row.id
            }
            let tasks = TasksModel(store: store, today: { snapshotDay })
            let quickEntry = QuickEntryModel(store: store, today: { snapshotDay })
            quickEntry.mode = .task
            quickEntry.text = "Taslak görevi gözden geçir"
            let notifications = NotificationService(center: FakeNotificationCenter(), defaults: defaults)
            // The evening reminder's route: `DayView` opens its own close-day sheet on the journal step.
            if screen == .closeDay { notifications.open(.journal) }
            let content = ChromeSheetsDuoContent(
                screen: screen, store: store, navigation: navigation, row: row,
                tasks: tasks, quickEntry: quickEntry
            )
            .environment(notifications)
            .environment(CalendarService(source: SnapshotCalendarSource()))
            .environment(location)
            .environment(GeofenceService(location: location, center: FakeGeofenceCenter(), defaults: defaults))
            .environment(IntentNavigation())
            .environment(\.clockNow, { snapshotNow })
            .environment(\.locale, snapshotLocale)
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.calendar, makeSnapshotCalendar())
            .environment(\.colorScheme, .light)
            // Pages the shell would hold (`MacNavigation` sets `.split` for its children); the
            // shell cases get it from `AdaptiveNavigation` itself, as in production.
            .environment(\.shellKind, screen.usesShell ? .tabs : .split)
            .environment(\.openSearch, {})
            .environment(\.openSettings, {})
            .tint(Color.ink.accent)
            .transaction { $0.animation = nil }
            var failure: (any Error)?
            await SnapshotHostGate.exclusive {
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                else {
                    Issue.record("Duo chrome needs the Journal test host's window scene.")
                    return
                }
                let animated = UIView.areAnimationsEnabled
                UIView.setAnimationsEnabled(false)
                defer { UIView.setAnimationsEnabled(animated) }
                let host = UIHostingController(rootView: AnyView(content))
                ShellCanvas.duoInner().applySizeClasses(to: host)
                host.traitOverrides.preferredContentSizeCategory = .medium
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: ShellCanvas.duoInner().size)
                window.overrideUserInterfaceStyle = .light
                window.rootViewController = host
                window.makeKeyAndVisible()
                // Wait for the presented content, then several idle frames like SnapshotHost.
                var idleFrames = 0
                for _ in 0..<80 where idleFrames < 8 {
                    try? await Task.sleep(for: .milliseconds(50))
                    host.view.layoutIfNeeded()
                    host.presentedViewController?.view.layoutIfNeeded()
                    let sheetReady = !screen.isSheet || host.presentedViewController?.view.window != nil
                    idleFrames = !store.isProcessing && sheetReady ? idleFrames + 1 : 0
                }
                do { try body(window, host) } catch { failure = error }
                // A column or sheet transition leaves a context that UIKit disposes after the next
                // commit; a window freed before that crashed the host (EXC_BAD_ACCESS in
                // `UIWindow dealloc`). Dismiss, let frames pass, and keep the window until the
                // next case starts.
                host.presentedViewController?.dismiss(animated: false)
                for _ in 0..<4 { try? await Task.sleep(for: .milliseconds(50)) }
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
                retired = window
            }
            if let failure { throw failure }
        }

        /// A list row or an input that is really on screen inside `root`: not hidden, with a
        /// non-zero frame, and inside the bounds of every ancestor up to `root` (a body given
        /// zero height still lays its cells out; they are then outside their container).
        static func hasVisibleRowOrField(in root: UIView) -> Bool {
            let rows = views(UICollectionView.self, under: root).flatMap(\.visibleCells)
            let fields: [UIView] =
                views(UITextField.self, under: root) + views(UITextView.self, under: root).map { $0 as UIView }
            return (rows + fields).contains { isOnScreen($0, in: root) }
        }

        static func isOnScreen(_ view: UIView, in root: UIView) -> Bool {
            guard !view.isHidden, view.bounds.height > 0 else { return false }
            let frame = view.convert(view.bounds, to: root)
            var ancestor = view.superview
            while let current = ancestor, current !== root {
                let clip = current.convert(current.bounds, to: root)
                guard !current.isHidden, frame.intersection(clip).height > 0 else { return false }
                ancestor = current.superview
            }
            return ancestor === root && frame.intersection(root.bounds).height > 0
        }

        static func views<T: UIView>(_ type: T.Type, under root: UIView) -> [T] {
            ((root as? T).map { [$0] } ?? [])
                + root.subviews.flatMap { views(type, under: $0) }
        }
    }

    private struct ChromeSheetsDuoContent: View {
        let screen: ChromeSheetsDuoCase
        let store: IndexStore
        let navigation: ShellNavigationState
        let row: TaskRow
        let tasks: TasksModel
        let quickEntry: QuickEntryModel
        @State private var presentsSheet = false

        var body: some View {
            Group {
                switch screen {
                case .today, .selectedTask, .settings:
                    AdaptiveNavigation(store: store, navigation: navigation, showsSettings: screen == .settings)
                case .kanbanPanel:
                    NavigationStack { KanbanView(tasks: tasks, showsFilters: true, selection: row) }
                case .taskDetail:
                    // Narrower than the panel threshold: the board presents its own sheet.
                    NavigationStack { KanbanView(tasks: tasks, showsFilters: true, selection: row) }
                        .frame(width: 600)
                case .quickEntry:
                    NavigationStack {
                        VStack {
                            InkPageTitle("Görev")
                            Spacer()
                            QuickEntryBar(store: store, isEnabled: true, model: quickEntry)
                        }
                        .inkPage()
                    }
                case .search, .closeDay:
                    NavigationStack { DayView(store: store, date: snapshotDay, isToday: true) }
                }
            }
            .onAppear { presentsSheet = screen == .search }
            // Search is the one sheet presented above the shell (`ContentView`), as in production.
            .sheet(isPresented: $presentsSheet) { SearchView(store: store) }
        }
    }
#endif
