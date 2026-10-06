#if os(iOS)
    import SnapshotTesting
    import Testing

    @testable import Journal

    /// Görevler listesi, kanban ve zaman çizelgesi: açık, koyu, AX3, Kontrastı Artır.
    /// Separate `@Test` methods (not `arguments:`) so a hung case can be re-recorded alone.
    @MainActor @Suite("Tasks screen snapshots", .serialized)
    struct TasksSnapshotTests {
        @Test func tasksLight() async throws { try await run(.tasksLight) }
        @Test func tasksDark() async throws { try await run(.tasksDark) }
        @Test func tasksAX3() async throws { try await run(.tasksAX3) }
        @Test func tasksContrast() async throws { try await run(.tasksContrast) }
        @Test func kanbanLight() async throws { try await run(.kanbanLight) }
        @Test func kanbanDark() async throws { try await run(.kanbanDark) }
        @Test func kanbanAX3() async throws { try await run(.kanbanAX3) }
        @Test func kanbanContrast() async throws { try await run(.kanbanContrast) }
        @Test func timelineLight() async throws { try await run(.timelineLight) }
        @Test func timelineDark() async throws { try await run(.timelineDark) }
        @Test func timelineAX3() async throws { try await run(.timelineAX3) }
        @Test func timelineContrast() async throws { try await run(.timelineContrast) }

        private func run(_ snapshotCase: TasksSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            await SnapshotHost.assert(
                snapshotCase, store: context.store, defaults: context.defaults.defaults)
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

    /// Mac kanban and timeline: weekend wells, today marker, completed outline bar, low priority.
    @MainActor @Suite("Tasks screen snapshots (macOS)", .serialized)
    struct TasksMacSnapshotTests {
        @Test func kanbanMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = CalendarDate("2026-09-20")!
            let tasks = TasksModel(store: context.store, today: { day })
            try await assertMacView(
                KanbanView(tasks: tasks),
                named: "kanbanMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: 1100, height: 720)
            )
        }

        @Test func timelineMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = CalendarDate("2026-09-20")!
            try Self.writeCompletedDatedTask(in: context.root)
            await context.store.refresh()
            let tasks = TasksModel(store: context.store, today: { day })
            let timeline = TimelineModel(tasks: tasks)
            timeline.scale = .week
            timeline.grouping = .none
            let weekStart = day.addingDays(-3) ?? day
            let weekEnd = day.addingDays(3) ?? day
            timeline.setVisibleRange(weekStart...weekEnd)
            #expect(!timeline.groups.flatMap(\.rows).isEmpty)
            try await assertMacView(
                TimelineMacSnapshotChrome(model: timeline),
                named: "timelineMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: 1100, height: 720)
            )
        }

        private func assertMacView<Content: View>(
            _ content: Content,
            named name: String,
            store: IndexStore,
            defaults: UserDefaults,
            size: CGSize
        ) async throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "tr_TR")
            calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
            let now = calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 41))!

            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { now }, timeZone: { calendar.timeZone })
            let calendarService = CalendarService(source: MacTasksSnapshotCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)

            let root =
                content
                .environment(notifications)
                .environment(calendarService)
                .environment(location)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                .environment(\.clockNow, { now })
                .environment(\.openSearch, {})
                .environment(\.colorScheme, .light)
                .frame(width: size.width, height: size.height)
                .background(Color.ink.paper)

            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
            for _ in 0..<40 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                if !store.isProcessing { break }
            }
            try? await Task.sleep(for: .milliseconds(800))
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(200))

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: host,
                as: .image(precision: 0.98, perceptualPrecision: 0.97),
                named: name,
                record: record,
                testName: "tasksMac"
            )
        }

        /// Open range 18–22 Sep completed on snapshot day → outline bar + filled end in week view.
        private static func writeCompletedDatedTask(in root: URL) throws {
            let file = root.appendingPathComponent("journal/2026-09-20.md")
            var text = try String(contentsOf: file, encoding: .utf8)
            let line =
                "- [x] Zaman çizelgesi tamamlanan örnek 🛫 2026-09-18 📅 2026-09-22 ✅ 2026-09-20 ^tlmdone\n"
            if let range = text.range(of: "## Events") {
                text.insert(contentsOf: line, at: range.lowerBound)
            } else {
                text += line
            }
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// Fixed week strip for Mac timeline references (avoids ScrollView geometry wiping `visibleRange`).
    private struct TimelineMacSnapshotChrome: View {
        let model: TimelineModel
        private var weekDays: [CalendarDate] {
            let start = model.visibleRange.lowerBound
            return (0..<7).compactMap { start.addingDays($0) }
        }

        var body: some View {
            let dayWidth: CGFloat = 96
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Görevler")
                        .font(.ink.section)
                        .frame(width: 220, height: 44, alignment: .leading)
                        .padding(.horizontal, 10)
                    HStack(spacing: 0) {
                        ForEach(weekDays, id: \.self) { day in
                            ZStack {
                                if day.weekday >= 5 { Color.ink.well }
                                if day == model.today { Color.ink.accent.opacity(0.12) }
                                if day == model.today {
                                    Text("Bugün")
                                        .font(.ink.meta)
                                        .foregroundStyle(.ink.accent)
                                        .fixedSize()
                                        .offset(y: -8)
                                }
                                Text(
                                    LocalDay.instant(for: day),
                                    format: .dateTime.day().month(.abbreviated)
                                )
                                .font(.ink.time)
                                .foregroundStyle(.ink.secondaryText)
                                .monospacedDigit()
                                .fixedSize()
                                .offset(y: day == model.today ? 8 : 0)
                            }
                            .frame(width: dayWidth, height: 44)
                        }
                    }
                }
                ForEach(model.groups) { group in
                    ForEach(group.rows.prefix(8)) { row in
                        let shift =
                            CGFloat(
                                model.visibleRange.lowerBound.ordinal
                                    - model.bounds.lowerBound.ordinal) * dayWidth
                        HStack(spacing: 0) {
                            LinkedTextView(text: row.text, store: model.store)
                                .font(.ink.content)
                                .lineLimit(2)
                                .frame(width: 220, height: 52, alignment: .leading)
                                .padding(.horizontal, 10)
                            TimelineBarView(model: model, row: row, dayWidth: dayWidth) {
                            } edit: { _ in
                            }
                            .frame(width: CGFloat(model.days.count) * dayWidth, height: 52)
                            .offset(x: -shift)
                            .frame(width: dayWidth * 7, height: 52, alignment: .leading)
                            .clipped()
                        }
                    }
                }
            }
            .background(Color.ink.paper)
        }
    }

    @MainActor private final class MacTasksSnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
