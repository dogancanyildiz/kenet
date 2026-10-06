#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Fixed calendar day for screens that group by "today". Sample vault days end 2026-09-27.
    let snapshotDay = CalendarDate("2026-09-20")!

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
        case medium, accessibility3
        var size: DynamicTypeSize {
            switch self {
            case .medium: .medium
            case .accessibility3: .accessibility3
            }
        }
        var contentSize: UIContentSizeCategory {
            switch self {
            case .medium: .medium
            case .accessibility3: .accessibilityLarge
            }
        }
    }

    /// Today screen × environment. Tasks cases live in ``TasksSnapshotCase``.
    enum ScreenSnapshotCase: String, CaseIterable, Sendable {
        case todayLight
        case todayDark
        case todayAX3
        case todayContrast

        var screen: SnapshotScreen { .today }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .todayDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .todayAX3: .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool {
            switch self {
            case .todayContrast: true
            default: false
            }
        }
    }

    /// Görevler listesi / kanban / zaman çizelgesi × ortam.
    enum TasksSnapshotCase: String, CaseIterable, Sendable {
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

    enum SnapshotScreen: String, Sendable {
        case today, tasks, kanban, timeline
    }

    @MainActor
    enum SnapshotHost {
        static func makeContext() throws -> TaskTestContext {
            try TaskTestContext(sample: true)
        }

        static func hostedView(screen: SnapshotScreen, store: IndexStore, defaults: UserDefaults)
            -> some View
        {
            defaults.set(TasksModel.Section.upcoming.rawValue, forKey: TasksModel.Section.storageKey)
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { snapshotNow },
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
            let root: AnyView =
                switch screen {
                case .today:
                    AnyView(DayView(store: store, date: snapshotDay, isToday: true))
                case .tasks, .kanban, .timeline:
                    AnyView(TasksView(store: store, tasks: tasks))
                }
            return NavigationStack { root }
                .environment(notifications)
                .environment(calendar)
                .environment(location)
                .environment(\.locale, snapshotLocale)
                .environment(\.calendar, makeSnapshotCalendar())
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.clockNow, { snapshotNow })
                .environment(\.openSearch, {})
        }

        static func assert(
            _ snapshotCase: ScreenSnapshotCase, store: IndexStore, defaults: UserDefaults,
            file: StaticString = #filePath, line: UInt = #line
        ) async {
            await capture(
                named: snapshotCase.rawValue,
                screen: snapshotCase.screen,
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                store: store,
                defaults: defaults,
                file: file,
                line: line,
                testName: "screen"
            )
        }

        static func assert(
            _ snapshotCase: TasksSnapshotCase, store: IndexStore, defaults: UserDefaults,
            file: StaticString = #filePath, line: UInt = #line
        ) async {
            await capture(
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

        private static func capture(
            named name: String,
            screen: SnapshotScreen,
            colorScheme: SnapshotColorScheme,
            dynamicType: SnapshotDynamicType,
            increaseContrast: Bool,
            store: IndexStore,
            defaults: UserDefaults,
            file: StaticString,
            line: UInt,
            testName: String
        ) async {
            let view = hostedView(screen: screen, store: store, defaults: defaults)
                .environment(\.colorScheme, colorScheme.colorScheme)
                .environment(\.dynamicTypeSize, dynamicType.size)
                .environment(\.calendar, makeSnapshotCalendar())
                .environment(\.clockNow, { snapshotNow })
                .transaction { $0.animation = nil }
                .frame(width: snapshotCanvasSize.width, height: snapshotCanvasSize.height)

            let traits = UITraitCollection { mutable in
                mutable.userInterfaceStyle = colorScheme.userInterfaceStyle
                mutable.preferredContentSizeCategory = dynamicType.contentSize
                mutable.accessibilityContrast = increaseContrast ? .high : .normal
                mutable.displayScale = 2
            }

            let previousAnimations = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(previousAnimations) }

            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = colorScheme.userInterfaceStyle
            host.view.frame = CGRect(origin: .zero, size: snapshotCanvasSize)

            let scene =
                UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window: UIWindow
            if let scene {
                window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: snapshotCanvasSize)
            } else {
                Issue.record("Snapshot host needs a UIWindowScene (run under the Journal test host).")
                return
            }
            window.overrideUserInterfaceStyle = colorScheme.userInterfaceStyle
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            for _ in 0..<40 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                if !store.isProcessing { break }
            }
            try? await Task.sleep(for: .milliseconds(800))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(200))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))

            let config = ViewImageConfig.iPhone13
            assertSnapshot(
                of: host,
                as: .image(
                    on: config,
                    precision: snapshotPrecision,
                    perceptualPrecision: snapshotPerceptualPrecision,
                    size: snapshotCanvasSize,
                    traits: traits
                ),
                named: name,
                record: record,
                file: file,
                testName: testName,
                line: line
            )
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func makeSnapshotCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = snapshotLocale
        calendar.timeZone = snapshotTimeZone
        return calendar
    }

    /// Denied calendar keeps EventKit chrome out of references.
    @MainActor private final class SnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
