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

    /// Shared non-Today screens. Today cases live in ``TodaySnapshotCase``.
    enum ScreenSnapshotCase: String, CaseIterable, Sendable {
        case tasksLight
        case tasksDark
        case tasksAX3
        case tasksContrast

        var screen: SnapshotScreen { .tasks }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .tasksDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .tasksAX3: .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool {
            switch self {
            case .tasksContrast: true
            default: false
            }
        }
    }

    enum SnapshotScreen: String, Sendable {
        case today, tasks
    }

    @MainActor
    enum SnapshotHost {
        static func makeContext() throws -> TaskTestContext {
            try TaskTestContext(sample: true)
        }

        static func hostedView(screen: SnapshotScreen, store: IndexStore, defaults: UserDefaults)
            -> some View
        {
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let calendar = CalendarService(source: SnapshotCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let root: AnyView =
                switch screen {
                case .today:
                    AnyView(DayView(store: store, date: snapshotDay, isToday: true))
                case .tasks:
                    AnyView(
                        TasksView(
                            store: store,
                            tasks: TasksModel(store: store, today: { snapshotDay })))
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
            await assertView(
                hostedView(screen: snapshotCase.screen, store: store, defaults: defaults),
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                named: snapshotCase.rawValue,
                store: store,
                testName: "screen",
                file: file,
                line: line
            )
        }

        static func assertView(
            _ root: some View,
            colorScheme: SnapshotColorScheme,
            dynamicType: SnapshotDynamicType,
            increaseContrast: Bool,
            named: String,
            store: IndexStore,
            size: CGSize = snapshotCanvasSize,
            /// Extra bottom safe area (e.g. tab bar) without an on-screen spacer that steals viewport.
            bottomSafeArea: CGFloat = 0,
            testName: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async {
            let view =
                root
                .environment(\.colorScheme, colorScheme.colorScheme)
                .environment(\.dynamicTypeSize, dynamicType.size)
                .environment(\.calendar, makeSnapshotCalendar())
                .environment(\.clockNow, { snapshotNow })
                .transaction { $0.animation = nil }
                .frame(width: size.width, height: size.height)

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
            host.additionalSafeAreaInsets.bottom = bottomSafeArea
            host.view.frame = CGRect(origin: .zero, size: size)

            let scene =
                UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window: UIWindow
            if let scene {
                window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: size)
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

            // Non-zero safeArea keeps SnapshotTesting from parking the view at (10000,10000),
            // which otherwise skips realistic inset layout for `safeAreaInset` chrome.
            let config = ViewImageConfig.iPhone13
            assertSnapshot(
                of: host,
                as: .image(
                    on: config,
                    precision: snapshotPrecision,
                    perceptualPrecision: snapshotPerceptualPrecision,
                    size: size,
                    traits: traits
                ),
                named: named,
                record: record,
                file: file,
                testName: testName,
                line: line
            )
            window.isHidden = true
            window.rootViewController = nil
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
