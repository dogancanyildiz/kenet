#if os(iOS)
    import Foundation
    import SnapshotTesting
    import Testing
    import VaultFormat

    @testable import Journal

    /// Bugün prototipi: açık, koyu, AX3, AX5, Kontrastı Artır, on devreden, boş gün.
    enum TodaySnapshotCase: String, CaseIterable, Sendable {
        case todayLight
        case todayDark
        case todayAX3
        case todayAX5
        case todayContrast
        case todayCarriedOver
        case todayEmpty

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
        var usesCarriedOver: Bool { self == .todayCarriedOver }
    }

    @MainActor @Suite("Today snapshots")
    struct TodaySnapshotTests {
        @Test(arguments: TodaySnapshotCase.allCases)
        func today(_ snapshotCase: TodaySnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            if snapshotCase.usesEmptyDay {
                try Self.writeEmptyDay(in: context.root)
            }
            if snapshotCase.usesCarriedOver {
                try Self.writeCarriedOverTasks(in: context.root)
            }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            await SnapshotHost.assertView(
                SnapshotHost.hostedView(screen: .today, store: context.store, defaults: context.defaults.defaults),
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                named: snapshotCase.rawValue,
                store: context.store,
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
            // Hide goal strip: rename goals folder so IndexStore finds none for this vault copy.
            let goals = root.appendingPathComponent("goals")
            if FileManager.default.fileExists(atPath: goals.path) {
                try FileManager.default.removeItem(at: goals)
            }
        }

        /// Ten open tasks due before snapshot day → three shown + "N devreden daha".
        private static func writeCarriedOverTasks(in root: URL) throws {
            try stripOpenTasksDueBeforeSnapshotDay(in: root)
            let file = root.appendingPathComponent("journal/2026-09-18.md")
            var text = try String(contentsOf: file, encoding: .utf8)
            var block = "\n"
            for index in 1...10 {
                block +=
                    "- [ ] Devreden örnek iş \(index) 📅 2026-09-\(String(format: "%02d", 10 + index % 8)) ^crr\(index)\n"
            }
            if let range = text.range(of: "## Events") {
                text.insert(contentsOf: block, at: range.lowerBound)
            } else {
                text += block
            }
            try text.write(to: file, atomically: true, encoding: .utf8)
        }

        /// Removes open checkbox tasks with a due date before the snapshot day.
        private static func stripOpenTasksDueBeforeSnapshotDay(in root: URL) throws {
            let journal = root.appendingPathComponent("journal")
            let files = try FileManager.default.contentsOfDirectory(
                at: journal, includingPropertiesForKeys: nil)
            // Open or in-progress checkboxes with a due/start day before snapshot day.
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
        @Test func todayMacLight() async throws {
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
            .frame(width: 720, height: 900)

            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
            for _ in 0..<40 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                if !context.store.isProcessing { break }
            }
            try? await Task.sleep(for: .milliseconds(800))

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: host,
                as: .image(precision: 0.98, perceptualPrecision: 0.97),
                named: "todayMacLight",
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
