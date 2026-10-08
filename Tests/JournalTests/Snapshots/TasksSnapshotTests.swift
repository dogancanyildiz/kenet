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
        private static let snapshotPrecision: Float = 0.9999
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

        @Test func tasksListSelectedMacLight() async throws {
            try await assertSelectedTaskList(named: "tasksListSelectedMacLight", appearance: .aqua)
        }

        @Test func tasksListSelectedMacDark() async throws {
            try await assertSelectedTaskList(named: "tasksListSelectedMacDark", appearance: .darkAqua)
        }

        @Test func daysListSelectedMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let days = context.store.content.days
            let id = try #require(days.first?.id)
            try await assertMacView(
                MacDayList(days: days, selection: .constant(id)),
                named: "daysListSelectedMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: 360, height: 480),
                inWindow: true
            )
        }

        @Test func peopleListSelectedMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let entities = EntityListQuery.entities(
                in: context.store.content, usage: context.store.entityUsage, kind: "person",
                search: "", order: .name)
            let id = try #require(entities.first?.id)
            try await assertMacView(
                MacEntityList(
                    store: context.store, entities: entities, showsUnseen: true,
                    selection: .constant(id)
                )
                .environment(IntentNavigation()),
                named: "peopleListSelectedMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: 360, height: 640),
                inWindow: true
            )
        }

        @Test func goalsListSelectedMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let id = try #require(context.store.content.goals.first?.id)
            try await assertMacView(
                GoalsView(store: context.store, selection: .constant(id)),
                named: "goalsListSelectedMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: 420, height: 640),
                inWindow: true
            )
        }

        // MARK: Sidebar and the list columns that gained a manşet

        @Test(arguments: [
            ("sidebarTasksMacLight", false, false), ("sidebarTasksMacDark", true, false),
            ("sidebarKanbanMacLight", false, true), ("sidebarKanbanMacDark", true, true),
        ])
        func sidebarSelection(name: String, dark: Bool, board: Bool) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            try await assertMacView(
                MacSidebarList(
                    entries: MacSidebar.entries(projects: context.store.content.projects),
                    selection: .constant(board ? .kanban : .section(.tasks))
                )
                // The offscreen window is never key; draw the row as the key window does.
                .environment(\.appearsActive, true),
                named: name,
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: InkSpacing.macSidebarIdealWidth, height: 560),
                appearance: dark ? .darkAqua : .aqua,
                inWindow: true
            )
        }

        @Test func sidebarInactiveWindowMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            try await assertMacView(
                MacSidebarList(
                    entries: MacSidebar.entries(projects: context.store.content.projects),
                    selection: .constant(.section(.tasks))
                )
                .environment(\.appearsActive, false),
                named: "sidebarInactiveWindowMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: InkSpacing.macSidebarIdealWidth, height: 560),
                inWindow: true
            )
        }

        @Test func daysColumnMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            try await assertMacView(
                MacDaysColumn(store: context.store, selection: .constant(nil)) {},
                named: "daysColumnMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: InkSpacing.macListIdealWidth, height: 720),
                inWindow: true
            )
        }

        @Test func peopleColumnMacLight() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            try await assertMacView(
                MacEntitiesColumn(
                    store: context.store, sectionTitle: "Kişiler", kind: .constant("person"),
                    order: .constant(.name), search: .constant(""), selection: .constant(nil)
                )
                .environment(IntentNavigation()),
                named: "peopleColumnMacLight",
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: InkSpacing.macListIdealWidth, height: 720),
                inWindow: true
            )
        }

        private func assertSelectedTaskList(named name: String, appearance: NSAppearance.Name) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = CalendarDate("2026-09-20")!
            let tasks = TasksModel(store: context.store, today: { day })
            let id = try #require(tasks.agenda.flatMap(\.rows).first?.id)
            try await assertMacView(
                TasksView(store: context.store, selection: .constant(id), tasks: tasks),
                named: name,
                store: context.store,
                defaults: context.defaults.defaults,
                size: CGSize(width: 420, height: 640),
                appearance: appearance,
                inWindow: true
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
            appearance: NSAppearance.Name = .aqua,
            inWindow: Bool = false
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
            // Lists draw nothing until the hosting view is in a window. Kanban and the
            // timeline already match references drawn without one, so only list snapshots opt in.
            let window: NSWindow? =
                inWindow
                ? NSWindow(
                    contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                : nil
            window?.contentView = host
            defer { window?.contentView = nil }
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
