#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    // Local inspection only (CI records authoritative Mac references; do not commit local PNGs):
    // SNAPSHOT_MAC_LOCAL=1 SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/TodayMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    @MainActor
    @Suite(
        "Today snapshots (macOS)",
        .enabled(
            if: MacSnapshotEnvironment.isEnabled,
            "Mac references belong to CI; set SNAPSHOT_MAC_LOCAL=1 for local inspection (do not commit)."))
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

            MacSnapshotEnvironment.requireOverlayScrollers()
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
            // On screen, so its scale would otherwise follow the display it opens on.
            let window = MacSnapshotWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)

            // Up to 20 s: on a loaded machine the goal strip can take longer than 5 s to settle.
            for _ in 0..<400 {
                await Task.yield()
                // Frame pump: SwiftUI and AppKit draw on a later run-loop turn and report no event to await.
                try? await Task.sleep(for: .milliseconds(50))
                if !context.store.isProcessing, ready.isReady { break }
            }
            #expect(ready.isReady, "goal strip must finish loading before the Mac reference is drawn")

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            // Fixed 2× bitmap (and window, see MacSnapshotWindow) so references do not depend on
            // the host display scale.
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: name,
                record: record,
                file: #filePath,
                testName: "today",
                line: #line
            )
            window.orderOut(nil)
        }

        /// The shared bar at the quick-entry panel's width and on its surface. The panel itself
        /// asks for focus when it opens; a caret would make the reference depend on its blink.
        @Test(arguments: ["quickEntryChipsMacLight", "quickEntryChipsMacDark"])
        func quickEntryChipsMac(_ name: String) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = context.today
            let model = QuickEntryModel(store: context.store, today: { day })
            model.languages = [.turkish, .english]
            model.mode = .task
            model.text = "!! yarın Deniz'i ara her hafta"

            let location = LocationService(
                source: FakeLocationSource(), defaults: context.defaults.defaults)
            let size = CGSize(width: 480, height: 120)
            let root = Color.ink.surface.safeAreaInset(edge: .bottom, spacing: 0) {
                QuickEntryBar(store: context.store, isEnabled: true, model: model)
            }
            .frame(width: size.width, height: size.height)
            .environment(location)
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .environment(\.colorScheme, name == "quickEntryChipsMacDark" ? .dark : .light)

            MacSnapshotEnvironment.requireOverlayScrollers()
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = MacSnapshotWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            for _ in 0..<400 {
                await Task.yield()
                // Frame pump: SwiftUI and AppKit draw on a later run-loop turn and report no event to await.
                try? await Task.sleep(for: .milliseconds(50))
                if !context.store.isProcessing { break }
            }
            // Last draw settles before the reference is taken; the references were recorded with this pause.
            try? await Task.sleep(for: .milliseconds(200))

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
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
