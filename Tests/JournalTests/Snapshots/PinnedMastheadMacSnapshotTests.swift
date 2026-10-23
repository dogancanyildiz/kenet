#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    // Local inspection only (CI records authoritative Mac references; do not commit local PNGs):
    // SNAPSHOT_MAC_LOCAL=1 SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/PinnedMastheadMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// Mac columns in the shortest window, scrolled: the day page keeps its manşet row pinned
    /// with a hairline under it, the Günlük column keeps its manşet, links and month above the
    /// scrolled days, the sidebar marks its top edge. The day page at rest has no hairline.
    @MainActor
    @Suite(
        "Pinned manşet snapshots (macOS)",
        .enabled(
            if: MacSnapshotEnvironment.isEnabled,
            "Mac references belong to CI; set SNAPSHOT_MAC_LOCAL=1 for local inspection (do not commit)."))
    struct PinnedMastheadMacSnapshotTests {
        /// The column heights of a 1000 × 560 window under its toolbar.
        private static let columnHeight: CGFloat = 500
        private static let day = CalendarDate("2026-09-25")!

        @Test(arguments: ["dayAtRestMacLight", "dayScrolledMacLight"])
        func dayPage(_ name: String) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let ready = PinnedGoalsReadyBox()
            let page = NavigationStack {
                DayView(store: context.store, date: Self.day)
            }
            .onPreferenceChange(GoalsStripReadyKey.self) { ready.isReady = $0 }
            let snapshot = try await Self.host(
                page, context: context, size: CGSize(width: 680, height: Self.columnHeight),
                dark: name.hasSuffix("Dark"), until: { ready.isReady })
            defer { snapshot.close() }
            if name.hasPrefix("dayScrolled") { try await snapshot.scroll(by: 360) }
            snapshot.assert(named: name, testName: "pinnedMasthead")
        }

        @Test func daysColumnScrolled() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let column = MacDaysColumn(store: context.store, selection: .constant("journal/2026-09-25.md")) {}
            let snapshot = try await Self.host(
                column, context: context, size: CGSize(width: InkSpacing.macListIdealWidth, height: Self.columnHeight))
            defer { snapshot.close() }
            try await snapshot.scroll(by: 300)
            snapshot.assert(named: "daysColumnScrolledMacLight", testName: "pinnedMasthead")
        }

        @Test func sidebarScrolled() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let projects = try await context.store.computeProjects()
            let sidebar = MacSidebarList(
                entries: MacSidebar.entries(projects: projects), selection: .constant(.section(.today)),
                onClick: { _ in }, restoresFocus: .constant(false))
            let snapshot = try await Self.host(
                sidebar, context: context, size: CGSize(width: InkSpacing.macSidebarIdealWidth, height: 360))
            defer { snapshot.close() }
            try await snapshot.scroll(by: 120)
            snapshot.assert(named: "sidebarScrolledMacLight", testName: "pinnedMasthead")
        }

        private static func host<V: View>(
            _ view: V, context: TaskTestContext, size: CGSize, dark: Bool = false,
            until ready: @escaping @MainActor () -> Bool = { true }
        ) async throws -> HostedSnapshot {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "tr_TR")
            calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9, minute: 41))!
            let defaults = context.defaults.defaults
            let root =
                view
                .environment(
                    NotificationService(
                        center: FakeNotificationCenter(), defaults: defaults, now: { now },
                        timeZone: { calendar.timeZone })
                )
                .environment(CalendarService(source: PinnedSnapshotCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                .environment(\.clockNow, { now })
                .environment(\.openSearch, {})
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: size.width, height: size.height)

            MacSnapshotEnvironment.requireOverlayScrollers()
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = MacSnapshotWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            var idle = 0
            for _ in 0..<400 {
                await Task.yield()
                // Frame pump: SwiftUI and AppKit draw on a later run-loop turn and report no event to await.
                try? await Task.sleep(for: .milliseconds(50))
                idle = context.store.isProcessing || !ready() ? 0 : idle + 1
                if idle >= 10 { break }
            }
            #expect(ready(), "the page must finish loading before the Mac reference is drawn")
            return HostedSnapshot(host: host, window: window)
        }
    }

    @MainActor
    private struct HostedSnapshot {
        let host: NSView
        let window: NSWindow

        /// Scrolls the view's (first vertical) scroll view by `distance` and lets it draw.
        func scroll(by distance: CGFloat) async throws {
            let scroll = try #require(
                Self.scrollViews(in: host).first {
                    ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height
                },
                "nothing to scroll")
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY + distance))
            scroll.reflectScrolledClipView(clip)
            for _ in 0..<12 {
                await Task.yield()
                // Frame pump: SwiftUI and AppKit draw on a later run-loop turn and report no event to await.
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        func assert(named name: String, testName: String, file: StaticString = #filePath, line: UInt = #line) {
            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: name, record: record, file: file, testName: testName, line: line)
        }

        func close() {
            window.orderOut(nil)
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            var found: [NSScrollView] = []
            func walk(_ view: NSView) {
                if let scroll = view as? NSScrollView { found.append(scroll) }
                view.subviews.forEach(walk)
            }
            walk(view)
            return found
        }

        private static func render(_ view: NSView, scale: CGFloat) -> NSImage {
            let size = view.bounds.size
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: max(1, Int((size.width * scale).rounded())),
                    pixelsHigh: max(1, Int((size.height * scale).rounded())), bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0)
            else { return NSImage(size: size) }
            rep.size = size
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            return image
        }
    }

    @MainActor private final class PinnedGoalsReadyBox {
        var isReady = false
    }

    @MainActor private final class PinnedSnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
