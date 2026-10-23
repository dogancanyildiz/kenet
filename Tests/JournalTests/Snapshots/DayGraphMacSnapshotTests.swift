#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    // Local inspection only (CI records authoritative Mac references; do not commit local PNGs):
    // SNAPSHOT_MAC_LOCAL=1 SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/DayGraphMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// The day's own graph and the day page's pinned manşet with its Graph icon, on the graph
    /// fixture vault (`Fixtures/vaults/graph`, 2026-10-01), in the Mac detail column's width.
    @MainActor
    @Suite(
        "Day graph snapshots (macOS)",
        .enabled(
            if: MacSnapshotEnvironment.isEnabled,
            "Mac references belong to CI; set SNAPSHOT_MAC_LOCAL=1 for local inspection (do not commit)."))
    struct DayGraphMacSnapshotTests {
        @Test(arguments: ["dayGraphMacLight", "dayMastheadMacLight"])
        func dayGraphMac(_ name: String) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/graph")
            try FileManager.default.copyItem(at: fixture, to: context.root)
            await context.start()
            #expect(context.store.lastUpdated != nil)

            let day = CalendarDate("2026-10-01")!
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "tr_TR")
            calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 41))!
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: context.defaults.defaults,
                now: { now }, timeZone: { calendar.timeZone })
            let calendarService = CalendarService(source: DayGraphMacCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: context.defaults.defaults)
            let store = context.store
            let isMasthead = name == "dayMastheadMacLight"
            let size = CGSize(width: 720, height: 900)
            let root = NavigationStack {
                if isMasthead {
                    DayView(store: store, date: day, isToday: true)
                } else {
                    GraphView(store: store, scope: .day(day), liveMotion: false)
                }
            }
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

            MacSnapshotEnvironment.requireOverlayScrollers()
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = MacSnapshotWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            // The page loads in a `.task` and the graph settles in the background: wait until the
            // index is idle across several frames.
            var idle = 0
            for _ in 0..<400 {
                await Task.yield()
                // Frame pump: SwiftUI and AppKit draw on a later run-loop turn and report no event to await.
                try? await Task.sleep(for: .milliseconds(50))
                idle = context.store.isProcessing ? 0 : idle + 1
                if idle >= 10 { break }
            }

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: name,
                record: record,
                file: #filePath,
                testName: "dayGraph",
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

    @MainActor private final class DayGraphMacCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
