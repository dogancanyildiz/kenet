#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Serializes UIWindow hosting across snapshot suites (they otherwise race on one scene).
    @MainActor
    enum SnapshotHostGate {
        private static var busy = false
        private static var waiters: [CheckedContinuation<Void, Never>] = []

        static func exclusive(_ work: () async -> Void) async {
            while busy {
                await withCheckedContinuation { waiters.append($0) }
            }
            busy = true
            defer {
                busy = false
                if !waiters.isEmpty {
                    waiters.removeFirst().resume()
                }
            }
            await work()
        }
    }

    /// Fixed calendar day for screens that group by "today". Sample vault days end 2026-09-27.
    let snapshotDay = CalendarDate("2026-09-20")!

    /// Goals list/detail: a day with incomplete (Spor 2/3) and partial (Kitap 15/20, Su 7/8) rings.
    let goalsSnapshotDay = CalendarDate("2026-09-17")!

    /// Phone-sized canvas shared by every case so references stay comparable across machines.
    let snapshotCanvasSize = CGSize(width: 390, height: 844)

    /// Locale kept Turkish so String Catalog copy matches the sample vault language.
    let snapshotLocale = Locale(identifier: "tr_TR")
    let snapshotTimeZone = TimeZone(secondsFromGMT: 3 * 3600)!

    /// Frozen wall clock (2026-09-20 09:41 in snapshotTimeZone). Injected via `\.clockNow`.
    let snapshotNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshotTimeZone
        return calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 41))!
    }()

    /// Frozen wall clock for goals screens (2026-09-17 09:41).
    let goalsSnapshotNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshotTimeZone
        return calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 17, hour: 9, minute: 41))!
    }()

    /// Cross-machine render noise (antialiasing, font hinting). Tuned after sensitivity probes
    /// (color / spacing / glyph); see report for the measurement table.
    let snapshotPrecision: Float = 0.999
    let snapshotPerceptualPrecision: Float = 0.995

    enum SnapshotColorScheme: String, CaseIterable, Sendable {
        case light, dark
        var colorScheme: ColorScheme { self == .light ? .light : .dark }
        var userInterfaceStyle: UIUserInterfaceStyle { self == .light ? .light : .dark }
    }

    enum SnapshotDynamicType: String, CaseIterable, Sendable {
        case medium, accessibility3, accessibility5
        var size: DynamicTypeSize {
            switch self {
            case .medium: .medium
            case .accessibility3: .accessibility3
            case .accessibility5: .accessibility5
            }
        }
        var contentSize: UIContentSizeCategory {
            switch self {
            case .medium: .medium
            case .accessibility3: .accessibilityLarge
            case .accessibility5: .accessibilityExtraExtraExtraLarge
            }
        }
    }

    /// Shared fields every screen-snapshot case exposes so hosts can share one assert path.
    protocol SnapshotCaseConfiguring: RawRepresentable where RawValue == String {
        var screen: SnapshotScreen { get }
        var colorScheme: SnapshotColorScheme { get }
        var dynamicType: SnapshotDynamicType { get }
        var increaseContrast: Bool { get }
    }

    /// Görevler listesi / kanban / zaman çizelgesi × ortam.
    enum TasksSnapshotCase: String, CaseIterable, Sendable, SnapshotCaseConfiguring {
        case tasksLight
        case tasksDark
        case tasksAX3
        case tasksContrast
        case kanbanLight
        case kanbanDark
        case kanbanAX3
        case kanbanContrast
        case timelineLight
        case timelineDark
        case timelineAX3
        case timelineContrast

        var screen: SnapshotScreen {
            switch self {
            case .tasksLight, .tasksDark, .tasksAX3, .tasksContrast: .tasks
            case .kanbanLight, .kanbanDark, .kanbanAX3, .kanbanContrast: .kanban
            case .timelineLight, .timelineDark, .timelineAX3, .timelineContrast: .timeline
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .tasksDark, .kanbanDark, .timelineDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .tasksAX3, .kanbanAX3, .timelineAX3: .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool {
            switch self {
            case .tasksContrast, .kanbanContrast, .timelineContrast: true
            default: false
            }
        }
    }

    /// Screens hosted by ``SnapshotHost/hostedView``. Today builds its own root in
    /// ``TodaySnapshotTests`` (calendar source, tab-bar inset, goal-strip readiness).
    enum SnapshotScreen: String, Sendable {
        case tasks, kanban, timeline
        case goals, summaries, graph, graphSelected, map, goalDetail, goalCreation
        case days, daysSelected, entity, search
    }

    @MainActor
    enum SnapshotHost {
        static func makeContext() throws -> TaskTestContext {
            try TaskTestContext(sample: true)
        }

        static func clock(for screen: SnapshotScreen) -> Date {
            switch screen {
            case .goals, .goalDetail, .goalCreation: goalsSnapshotNow
            default: snapshotNow
            }
        }

        static func hostedView(screen: SnapshotScreen, store: IndexStore, defaults: UserDefaults)
            -> some View
        {
            defaults.set(TasksModel.Section.upcoming.rawValue, forKey: TasksModel.Section.storageKey)
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { Self.clock(for: screen) },
                timeZone: { snapshotTimeZone })
            let calendar = CalendarService(source: SnapshotCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let tasks = TasksModel(store: store, today: { snapshotDay })
            switch screen {
            case .kanban:
                tasks.section = .kanban
                defaults.set(TasksModel.Section.kanban.rawValue, forKey: TasksModel.Section.storageKey)
            case .timeline:
                tasks.section = .timeline
                defaults.set(TasksModel.Section.timeline.rawValue, forKey: TasksModel.Section.storageKey)
            default:
                break
            }
            let intent = IntentNavigation()
            let clock = clock(for: screen)
            let root: AnyView =
                switch screen {
                case .tasks, .kanban, .timeline:
                    AnyView(TasksView(store: store, tasks: tasks))
                case .goals:
                    AnyView(GoalsView(store: store))
                case .summaries:
                    AnyView(SummariesView(store: store, today: { snapshotDay }))
                case .graph:
                    AnyView(GraphView(store: store, liveMotion: false))
                case .graphSelected:
                    AnyView(GraphView(store: store, focus: "people/Ece Yalın.md", liveMotion: false))
                case .map:
                    AnyView(PlacesMapView(store: store))
                case .goalDetail:
                    AnyView(goalDetailView(store: store, day: goalsSnapshotDay))
                case .goalCreation:
                    AnyView(GoalCreationView(store: store))
                case .days:
                    AnyView(DaysView(store: store))
                case .daysSelected:
                    AnyView(DaysView(store: store, previewSelectedDay: snapshotDay))
                case .entity:
                    AnyView(
                        EntityView(
                            store: store,
                            entity: store.content.entities.first { $0.name == "Deniz Arıkan" }
                                ?? store.content.entities[0]))
                case .search:
                    AnyView(SearchView(store: store, initialQuery: "Deniz"))
                }
            return NavigationStack { root }
                .environment(notifications)
                .environment(calendar)
                .environment(location)
                .environment(intent)
                .environment(\.locale, snapshotLocale)
                .environment(\.calendar, makeSnapshotCalendar())
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.clockNow, { clock })
                .environment(\.openSearch, {})
                .environment(\.openSettings, {})
        }

        private static func goalDetailView(store: IndexStore, day: CalendarDate) -> some View {
            let goal =
                store.content.goals.first { $0.key == "kitap" }
                ?? store.content.goals[0]
            return GoalDetailView(store: store, goal: goal, day: day)
        }

        static func assert(
            _ snapshotCase: some SnapshotCaseConfiguring, store: IndexStore, defaults: UserDefaults,
            file: StaticString = #filePath, line: UInt = #line, testName: String = "screen"
        ) async {
            await assert(
                named: snapshotCase.rawValue,
                screen: snapshotCase.screen,
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                store: store,
                defaults: defaults,
                file: file,
                line: line,
                testName: testName
            )
        }

        /// Tasks references keep their own `tasksScreen.<case>.png` prefix.
        static func assert(
            _ snapshotCase: TasksSnapshotCase, store: IndexStore, defaults: UserDefaults,
            file: StaticString = #filePath, line: UInt = #line
        ) async {
            await assert(
                named: snapshotCase.rawValue,
                screen: snapshotCase.screen,
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                store: store,
                defaults: defaults,
                file: file,
                line: line,
                testName: "tasksScreen"
            )
        }

        /// Goal detail needs a tall canvas (heatmap + definition + history); AX3 taller still.
        static func canvasSize(
            for screen: SnapshotScreen, dynamicType: SnapshotDynamicType = .medium
        ) -> CGSize {
            switch screen {
            case .goalDetail:
                dynamicType == .accessibility3
                    ? CGSize(width: 390, height: 2600)
                    : CGSize(width: 390, height: 1800)
            default: snapshotCanvasSize
            }
        }

        /// Case-based entry: builds the shared ``hostedView`` and funnels into ``assertView``.
        static func assert(
            named name: String,
            screen: SnapshotScreen,
            colorScheme: SnapshotColorScheme,
            dynamicType: SnapshotDynamicType,
            increaseContrast: Bool,
            store: IndexStore,
            defaults: UserDefaults,
            file: StaticString = #filePath,
            line: UInt = #line,
            testName: String = "screen"
        ) async {
            await assertView(
                colorScheme: colorScheme,
                dynamicType: dynamicType,
                increaseContrast: increaseContrast,
                named: name,
                store: store,
                size: canvasSize(for: screen, dynamicType: dynamicType),
                clock: clock(for: screen),
                testName: testName,
                file: file,
                line: line
            ) {
                hostedView(screen: screen, store: store, defaults: defaults)
            }
        }

        /// The single capture path: every `assert` funnels here, under the host gate.
        /// `content` is built inside the gate; `isReady` adds a screen-specific load condition
        /// (e.g. the Today goal strip) on top of the index going idle.
        static func assertView<Content: View>(
            colorScheme: SnapshotColorScheme,
            dynamicType: SnapshotDynamicType,
            increaseContrast: Bool,
            named name: String,
            store: IndexStore,
            size canvas: CGSize = snapshotCanvasSize,
            /// Extra bottom safe area (e.g. tab bar) without an on-screen spacer that steals viewport.
            bottomSafeArea: CGFloat = 0,
            clock: Date = snapshotNow,
            isReady: @MainActor () -> Bool = { true },
            testName: String,
            file: StaticString = #filePath,
            line: UInt = #line,
            @ViewBuilder content: @MainActor () -> Content
        ) async {
            await SnapshotHostGate.exclusive {
                // colorSchemeContrast is set only via UITraitCollection (not a writable EnvironmentValues key).
                let view = content()
                    .environment(\.colorScheme, colorScheme.colorScheme)
                    .environment(\.dynamicTypeSize, dynamicType.size)
                    .environment(\.calendar, makeSnapshotCalendar())
                    .environment(\.clockNow, { clock })
                    .transaction { $0.animation = nil }
                    .frame(width: canvas.width, height: canvas.height)

                let traits = UITraitCollection { mutable in
                    mutable.userInterfaceStyle = colorScheme.userInterfaceStyle
                    mutable.preferredContentSizeCategory = dynamicType.contentSize
                    mutable.accessibilityContrast = increaseContrast ? .high : .normal
                    mutable.displayScale = 2
                }

                // Host in a window first so `.task` (goal strip load) runs before the pixel capture.
                let previousAnimations = UIView.areAnimationsEnabled
                UIView.setAnimationsEnabled(false)
                defer { UIView.setAnimationsEnabled(previousAnimations) }

                let host = UIHostingController(rootView: view)
                host.overrideUserInterfaceStyle = colorScheme.userInterfaceStyle
                host.traitOverrides.preferredContentSizeCategory = dynamicType.contentSize
                host.traitOverrides.accessibilityContrast = increaseContrast ? .high : .normal
                host.additionalSafeAreaInsets.bottom = bottomSafeArea
                host.view.frame = CGRect(origin: .zero, size: canvas)

                let scene =
                    UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
                    ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                guard let scene else {
                    Issue.record(
                        "Snapshot host needs a UIWindowScene (run under the Journal test host).")
                    return
                }
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: canvas)
                window.overrideUserInterfaceStyle = colorScheme.userInterfaceStyle
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    window.windowScene = nil
                }
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                // Index + goal-strip `.task`: wait until processing stays idle across several frames.
                var idlePasses = 0
                for _ in 0..<80 {
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(50))
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    if store.isProcessing || !isReady() {
                        idlePasses = 0
                        continue
                    }
                    idlePasses += 1
                    if idlePasses >= 8 { break }
                }
                if !isReady() {
                    Issue.record("Snapshot \(name): screen never reported ready before capture.")
                }

                let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                    .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))

                // Non-zero safeArea keeps SnapshotTesting from parking the view at (10000,10000),
                // which otherwise skips realistic inset layout for `safeAreaInset` chrome.
                let config = ViewImageConfig.iPhone13
                assertSnapshot(
                    of: host,
                    as: .image(
                        on: config,
                        precision: snapshotPrecision,
                        perceptualPrecision: snapshotPerceptualPrecision,
                        size: canvas,
                        traits: traits
                    ),
                    named: name,
                    record: record,
                    file: file,
                    testName: testName,
                    line: line
                )
            }
        }
    }

    func makeSnapshotCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = snapshotLocale
        calendar.timeZone = snapshotTimeZone
        return calendar
    }

    /// Denied calendar keeps EventKit chrome out of references.
    @MainActor final class SnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif

#if os(macOS)
    import AppKit
    import Testing

    /// Window for Mac references. A hosted SwiftUI view takes two things from its window, and a
    /// plain `NSWindow` takes both from the main display, so docking the Mac to an external
    /// monitor changed the bitmap of an unchanged view:
    /// - backing scale: on a 1× monitor the view drew at 1× (blurred text, 1 pt hairlines,
    ///   whole-point layout) into the 2× bitmap;
    /// - colour space: text SwiftUI rasterises itself (mention links) came out one level off on
    ///   its antialiased edges under the monitor's profile.
    /// Both are pinned to what the references were recorded with (built-in Retina display).
    final class MacSnapshotWindow: NSWindow {
        static let scale: CGFloat = 2

        override init(
            contentRect: NSRect, styleMask style: NSWindow.StyleMask,
            backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool
        ) {
            super.init(
                contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
            colorSpace = .displayP3
        }

        override var backingScaleFactor: CGFloat { Self.scale }
    }

    @MainActor
    enum MacSnapshotEnvironment {
        /// Scroll bars follow the pointing device unless told otherwise: with a mouse connected
        /// AppKit switches to legacy scrollers, which take width from every overflowing list and
        /// move its content. The `Journal_macOS` test action pins the overlay style with a launch
        /// argument (project.yml); this turns a run without it into a readable failure instead
        /// of a pixel diff.
        static func requireOverlayScrollers(sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(
                NSScroller.preferredScrollerStyle == .overlay,
                "Mac references are drawn with overlay scroll bars; run through the Journal_macOS scheme (-AppleShowScrollBars WhenScrolling).",
                sourceLocation: sourceLocation)
        }
    }
#endif
