#if os(iOS)
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Bugün prototipi: açık, koyu, AX3, AX5, Kontrastı Artır, on devreden, boş gün,
    /// öncelik/devam, uzun tuval (takvim + günlük), boolean hedef.
    enum TodaySnapshotCase: String, CaseIterable, Sendable {
        case todayLight
        case todayDark
        case todayAX3
        case todayAX5
        case todayContrast
        case todayCarriedOver
        case todayEmpty
        case todayPriority
        case todayTall
        case todayGoals

        var colorScheme: SnapshotColorScheme {
            self == .todayDark ? .dark : .light
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .todayAX3: .accessibility3
            case .todayAX5: .accessibility5
            default: .medium
            }
        }

        var increaseContrast: Bool { self == .todayContrast }
        var usesEmptyDay: Bool { self == .todayEmpty }
        var usesCarriedOver: Bool { self == .todayCarriedOver || self == .todayPriority }
        var usesPriorityExtras: Bool { self == .todayPriority }
        var usesTallCanvas: Bool { self == .todayTall }
        var usesCalendar: Bool { self == .todayTall }
        /// Incomplete boolean lives in `todayGoals` so the main light reference keeps first-event room.
        var usesIncompleteBooleanGoal: Bool { self == .todayGoals }
    }

    @MainActor @Suite("Today snapshots")
    struct TodaySnapshotTests {
        /// Approximate tab-bar height so the quick-entry shelf is not flush with the canvas bottom.
        private static let tabBarHeight: CGFloat = 49

        @Test(arguments: TodaySnapshotCase.allCases)
        func today(_ snapshotCase: TodaySnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            if snapshotCase.usesEmptyDay {
                try Self.writeEmptyDay(in: context.root)
            }
            if snapshotCase.usesCarriedOver {
                try Self.writeCarriedOverTasks(
                    in: context.root, includePriorityExtras: snapshotCase.usesPriorityExtras)
            }
            if snapshotCase.usesIncompleteBooleanGoal {
                try Self.writeIncompleteBooleanGoal(in: context.root)
            }
            await context.start()
            #expect(context.store.lastUpdated != nil)

            let calendarSource: any CalendarEventSource =
                snapshotCase.usesCalendar
                ? TodaySnapshotCalendarSource(events: Self.sampleCalendarEvents())
                : SnapshotCalendarSource()
            let defaults = context.defaults.defaults
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let calendar = CalendarService(source: calendarSource)
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let root = NavigationStack {
                DayView(store: context.store, date: snapshotDay, isToday: true)
            }
            .environment(notifications)
            .environment(calendar)
            .environment(location)
            .environment(\.locale, snapshotLocale)
            .environment(\.calendar, makeSnapshotCalendar())
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.clockNow, { snapshotNow })
            .environment(\.openSearch, {})

            if snapshotCase.usesCalendar {
                await calendar.load(snapshotDay, timeZone: snapshotTimeZone)
            }

            let size =
                snapshotCase.usesTallCanvas
                ? CGSize(width: 390, height: 1600) : snapshotCanvasSize
            await SnapshotHost.assertView(
                root,
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                named: snapshotCase.rawValue,
                store: context.store,
                size: size,
                bottomSafeArea: Self.tabBarHeight,
                testName: "today",
                file: #filePath,
                line: #line
            )
        }

        /// Empty journal day + no open carried-over tasks/goals so EmptyState is visible.
        private static func writeEmptyDay(in root: URL) throws {
            let file = root.appendingPathComponent("journal/2026-09-20.md")
            let body = """
                ---
                type: journal
                date: 2026-09-20
                ---

                ## Tasks

                ## Events

                ## Journal

                """
            try body.write(to: file, atomically: true, encoding: .utf8)
            try stripOpenTasksDueBeforeSnapshotDay(in: root)
            let goals = root.appendingPathComponent("goals")
            if FileManager.default.fileExists(atPath: goals.path) {
                try FileManager.default.removeItem(at: goals)
            }
        }

        /// Ten open tasks due before snapshot day → three shown + "N devreden daha".
        private static func writeCarriedOverTasks(
            in root: URL, includePriorityExtras: Bool
        ) throws {
            try stripOpenTasksDueBeforeSnapshotDay(in: root)
            let file = root.appendingPathComponent("journal/2026-09-18.md")
            var text = try String(contentsOf: file, encoding: .utf8)
            var block = "\n"
            for index in 1...10 {
                block +=
                    "- [ ] Devreden örnek iş \(index) 📅 2026-09-\(String(format: "%02d", 10 + index % 8)) ^crr\(index)\n"
            }
            // Earliest due dates + higher priority so TasksModel.order keeps them in the first three.
            if includePriorityExtras {
                block =
                    "\n- [ ] Yüksek öncelikli açık ⏫ 📅 2026-09-01 ^hi1\n"
                    + "- [/] Orta öncelikli devam 🔼 📅 2026-09-02 ^med1\n"
                    + String(block.dropFirst())
            }
            if let range = text.range(of: "## Events") {
                text.insert(contentsOf: block, at: range.lowerBound)
            } else {
                text += block
            }
            try text.write(to: file, atomically: true, encoding: .utf8)
        }

        private static func writeIncompleteBooleanGoal(in root: URL) throws {
            let file = root.appendingPathComponent("goals/Meditasyon.md")
            let body = """
                ---
                type: goal
                name: Meditasyon
                key: meditasyon
                period: day
                kind: boolean
                target: 1
                ---
                """
            try body.write(to: file, atomically: true, encoding: .utf8)
        }

        private static func stripOpenTasksDueBeforeSnapshotDay(in root: URL) throws {
            let journal = root.appendingPathComponent("journal")
            let files = try FileManager.default.contentsOfDirectory(
                at: journal, includingPropertiesForKeys: nil)
            let openTask = try NSRegularExpression(
                pattern: #"^- \[[ /]\] .*(?:📅|🛫) 2026-09-(0[1-9]|1[0-9])\b.*$"#,
                options: .anchorsMatchLines)
            for file in files where file.pathExtension == "md" {
                var text = try String(contentsOf: file, encoding: .utf8)
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = openTask.stringByReplacingMatches(
                    in: text, options: [], range: range, withTemplate: "")
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
        }

        private static func sampleCalendarEvents() -> [CalendarEvent] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = snapshotTimeZone
            let start1 = calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0))!
            let end1 = calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 20, hour: 11, minute: 0))!
            let start2 = calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 20, hour: 14, minute: 30))!
            let end2 = calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 20, hour: 15, minute: 0))!
            let tint = CalendarEventColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
            return [
                CalendarEvent(
                    id: "cal-1", title: "Örnek toplantı", start: start1, end: end1, isAllDay: false,
                    color: tint),
                CalendarEvent(
                    id: "cal-2", title: "Kurgusal kahve", start: start2, end: end2, isAllDay: false,
                    color: tint),
            ]
        }
    }

    @MainActor private final class TodaySnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.fullAccess
        var onChange: (@MainActor @Sendable () -> Void)?
        private let stored: [CalendarEvent]
        init(events: [CalendarEvent]) { stored = events }
        func requestFullAccess() async throws -> Bool { true }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
            stored.filter { $0.start < end && $0.end > start }
        }
    }
#endif

#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    @MainActor @Suite("Today snapshots (macOS)")
    struct TodayMacSnapshotTests {
        @Test(arguments: ["todayMacLight", "todayMacDark"])
        func todayMac(_ name: String) async throws {
            // References are drawn with Turkish catalog + tr_TR formatting. `-testLanguage en`
            // still nudges system chrome enough to miss the 0.999 pixel floor.
            guard Locale.current.language.languageCode?.identifier == "tr" else { return }

            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)

            let day = CalendarDate("2026-09-20")!
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "tr_TR")
            calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
            let now = calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 41))!

            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: context.defaults.defaults,
                now: { now }, timeZone: { calendar.timeZone })
            let calendarService = CalendarService(source: MacSnapshotCalendarSource())
            let location = LocationService(
                source: FakeLocationSource(), defaults: context.defaults.defaults)
            let scheme: ColorScheme = name == "todayMacDark" ? .dark : .light

            let root = NavigationStack {
                DayView(store: context.store, date: day, isToday: true)
            }
            .environment(notifications)
            .environment(calendarService)
            .environment(location)
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.clockNow, { now })
            .environment(\.openSearch, {})
            .environment(\.colorScheme, scheme)
            .frame(width: 720, height: 900)

            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
            for _ in 0..<80 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                if !context.store.isProcessing { break }
            }
            // Wait until goal strip finished loading so plus controls are present.
            try? await Task.sleep(for: .milliseconds(1200))

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: host,
                as: .image(precision: 0.999, perceptualPrecision: 0.995),
                named: name,
                record: record,
                testName: "today"
            )
        }
    }

    @MainActor private final class MacSnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
