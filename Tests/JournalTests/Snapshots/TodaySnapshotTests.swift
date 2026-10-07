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
        /// Tab bar + home indicator so the quick-entry shelf matches a real phone bottom inset.
        private static let tabBarHeight: CGFloat = 84

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
            if snapshotCase.usesCalendar {
                await calendar.load(snapshotDay, timeZone: snapshotTimeZone)
            }

            // The goal strip loads in a `.task`; without this the reference can catch its spinner.
            let goalsReady = GoalsReadyBox()
            let store = context.store
            let size =
                snapshotCase.usesTallCanvas
                ? CGSize(width: 390, height: 1600) : snapshotCanvasSize
            let root = NavigationStack {
                DayView(store: store, date: snapshotDay, isToday: true)
            }
            .environment(notifications)
            .environment(calendar)
            .environment(location)
            .environment(\.locale, snapshotLocale)
            .environment(\.calendar, makeSnapshotCalendar())
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.clockNow, { snapshotNow })
            .environment(\.openSearch, {})
            // Without an action the masthead hides its Settings button.
            .environment(\.openSettings, {})
            .onPreferenceChange(GoalsStripReadyKey.self) { goalsReady.isReady = $0 }
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                named: snapshotCase.rawValue,
                store: store,
                size: size,
                bottomSafeArea: Self.tabBarHeight,
                isReady: { store.content.goals.isEmpty || goalsReady.isReady },
                testName: "today",
                file: #filePath,
                line: #line,
                content: { root }
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

    @MainActor private final class GoalsReadyBox {
        var isReady = false
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

    // Local record (macOS; does not use the iOS simulator):
    // SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/TodayMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    @MainActor @Suite("Today snapshots (macOS)")
    struct TodayMacSnapshotTests {
        @Test(arguments: ["todayMacLight", "todayMacDark"])
        func todayMac(_ name: String) async throws {
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

            let ready = MacGoalsReadyBox()
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
            .onPreferenceChange(GoalsStripReadyKey.self) { ready.isReady = $0 }
            .frame(width: 720, height: 900)

            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)

            for _ in 0..<100 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                if !context.store.isProcessing, ready.isReady { break }
            }
            #expect(ready.isReady, "goal strip must finish loading before the Mac reference is drawn")

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            // Fixed 2× bitmap so references do not depend on the host display scale.
            assertSnapshot(
                of: Self.render(host, scale: 2),
                as: .image(precision: 0.999, perceptualPrecision: 0.995),
                named: name,
                record: record,
                file: #filePath,
                testName: "today",
                line: #line
            )
            window.orderOut(nil)
        }

        private static func render(_ view: NSView, scale: CGFloat) -> NSImage {
            let size = view.bounds.size
            let pixelsWide = max(1, Int((size.width * scale).rounded()))
            let pixelsHigh = max(1, Int((size.height * scale).rounded()))
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else {
                return NSImage(size: size)
            }
            rep.size = size
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            return image
        }
    }

    @MainActor private final class MacGoalsReadyBox {
        var isReady = false
    }

    @MainActor private final class MacSnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
