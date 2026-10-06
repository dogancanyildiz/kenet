#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Fixed wall clock for screens that group by "today". Sample vault days end 2026-09-27.
    let snapshotDay = CalendarDate("2026-09-20")!

    /// Phone-sized canvas shared by every case so references stay comparable across machines.
    let snapshotCanvasSize = CGSize(width: 390, height: 844)

    /// Locale kept Turkish so String Catalog copy matches the sample vault language.
    let snapshotLocale = Locale(identifier: "tr_TR")
    let snapshotTimeZone = TimeZone(secondsFromGMT: 3 * 3600)!

    /// Cross-machine render noise (antialiasing, font hinting). Exact pixel `precision` is 0.99
    /// (allows ~1% subpixel churn). Perceptual floor 0.98 rejects intentional layout edits: a 1 pt
    /// canvas height change fails all eight cases; identical consecutive runs score above both.
    let snapshotPerceptualPrecision: Float = 0.98

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

    /// One screen × one environment. Adding a case is a single enum line.
    enum ScreenSnapshotCase: String, CaseIterable, Sendable {
        case todayLight
        case todayDark
        case todayAX3
        case todayContrast
        case tasksLight
        case tasksDark
        case tasksAX3
        case tasksContrast

        var screen: SnapshotScreen {
            switch self {
            case .todayLight, .todayDark, .todayAX3, .todayContrast: .today
            case .tasksLight, .tasksDark, .tasksAX3, .tasksContrast: .tasks
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .todayDark, .tasksDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .todayAX3, .tasksAX3: .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool {
            switch self {
            case .todayContrast, .tasksContrast: true
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

        static func hostedView(screen: SnapshotScreen, store: IndexStore, defaults: UserDefaults) -> some View {
            let fixedNow = LocalDay.instant(for: snapshotDay, timeZone: snapshotTimeZone)
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { fixedNow },
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
                .environment(\.openSearch, {})
        }

        static func assert(
            _ snapshotCase: ScreenSnapshotCase, store: IndexStore, defaults: UserDefaults,
            file: StaticString = #filePath, line: UInt = #line
        ) async {
            // colorSchemeContrast is set only via UITraitCollection (not a writable EnvironmentValues key).
            let view = hostedView(screen: snapshotCase.screen, store: store, defaults: defaults)
                .environment(\.colorScheme, snapshotCase.colorScheme.colorScheme)
                .environment(\.dynamicTypeSize, snapshotCase.dynamicType.size)
                .environment(\.calendar, makeSnapshotCalendar())
                .transaction { $0.animation = nil }
                .frame(width: snapshotCanvasSize.width, height: snapshotCanvasSize.height)

            let traits = UITraitCollection { mutable in
                mutable.userInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
                mutable.preferredContentSizeCategory = snapshotCase.dynamicType.contentSize
                mutable.accessibilityContrast = snapshotCase.increaseContrast ? .high : .normal
                mutable.displayScale = 2
            }

            // Host in a window first so `.task` (goal strip load) runs before the pixel capture.
            // Sleeping before assertSnapshot is useless: SnapshotTesting creates the host itself.
            let previousAnimations = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(previousAnimations) }

            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
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
                // Fallback for hosts without a scene yet: size-only window via deprecated path is
                // unavailable under warnings-as-errors; fail clearly instead of silent blank frames.
                Issue.record("Snapshot host needs a UIWindowScene (run under the Journal test host).")
                return
            }
            window.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
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
            // Goal strip's `.task` fetch finishes after the first index publish.
            try? await Task.sleep(for: .milliseconds(800))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            // Second frame after load: ProgressView must be gone before capture.
            try? await Task.sleep(for: .milliseconds(200))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))

            assertSnapshot(
                of: host,
                as: .image(
                    precision: 0.99,
                    perceptualPrecision: snapshotPerceptualPrecision,
                    size: snapshotCanvasSize,
                    traits: traits
                ),
                named: snapshotCase.rawValue,
                record: record,
                file: file,
                testName: "screen",
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
