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
    // Record / verify Mac references (no simulator; local only — CI skips Mac image suites):
    // SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS \
    //   -destination 'platform=macOS' -only-testing:JournalTests_macOS/TasksMacSnapshotTests \
    //   CODE_SIGNING_ALLOWED=NO
    // Then the same command with SNAPSHOT_TESTING_RECORD=never three times.
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Mac kanban and timeline: weekend wells, today marker, completed outline bar, low priority.
    @MainActor @Suite("Tasks screen snapshots (macOS)", .serialized)
    struct TasksMacSnapshotTests {
        private static let snapshotPrecision: Float = 0.999
        private static let snapshotPerceptualPrecision: Float = 0.995
        private static let bitmapScale: CGFloat = 2

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
            let weekDays = (0..<7).compactMap { weekStart.addingDays($0) }
            try await assertMacView(
                TimelineDesktopContent(
                    model: timeline,
                    days: weekDays,
                    dayWidth: 96,
                    select: { _ in },
                    edit: { _, _ in },
                    maxRowsPerGroup: 8
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.ink.paper),
                named: "timelineMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: 1100, height: 720)
            )
        }

        /// Page top of the full-width timeline: manşet row with its three icons (group, filter,
        /// search), the tabs and the single "Ölçek" menu row. Framed to the top of the window.
        @Test func timelineTopMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = CalendarDate("2026-09-20")!
            let tasks = TasksModel(store: context.store, today: { day })
            try await assertMacView(
                TaskTimelineView(tasks: tasks, showsFilters: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
                named: "timelineTopMacLight",
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
            size: CGSize,
            appearance: NSAppearance.Name = .aqua
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
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
                .tint(Color.ink.accent)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ink.paper)

            let host = NSHostingView(rootView: root)
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor(Color.ink.paper).cgColor
            for _ in 0..<40 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                if !store.isProcessing { break }
            }
            try? await Task.sleep(for: .milliseconds(800))
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(200))

            let image = Self.renderFixedScaleImage(from: host, scale: Self.bitmapScale)
            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: image,
                as: .image(
                    precision: Self.snapshotPrecision,
                    perceptualPrecision: Self.snapshotPerceptualPrecision),
                named: name,
                record: record,
                testName: "tasksMac"
            )
        }

        /// Screen-independent bitmap: point size × fixed scale (not the display backing scale).
        private static func renderFixedScaleImage(from view: NSView, scale: CGFloat) -> NSImage {
            let size = view.bounds.size
            let pixelsWide = Int((size.width * scale).rounded())
            let pixelsHigh = Int((size.height * scale).rounded())
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: pixelsWide,
                    pixelsHigh: pixelsHigh,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0)
            else {
                fatalError("Mac snapshot bitmap could not be created")
            }
            rep.size = size
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            return image
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

    @MainActor private final class MacTasksSnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
