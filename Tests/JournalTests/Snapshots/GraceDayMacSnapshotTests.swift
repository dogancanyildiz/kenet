#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    // Local record (macOS; does not use the iOS simulator):
    // SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/GraceDayMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// The goal page of the fictional ``GraceDayVault`` on the Mac: the balance line and the
    /// heatmap's chain-day marks; and the Goals list column with the badge after the streak.
    @MainActor
    @Suite(
        "Chain day snapshots (macOS)",
        .enabled(if: MacSnapshotEnvironment.isEnabled, "Mac references are recorded by CI."))
    struct GraceDayMacSnapshotTests {
        @Test(arguments: ["goalDetailMacLight", "goalsListMacLight"])
        func goalDetailMac(_ name: String) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            try GraceDayVault.generate(at: context.root)
            await context.start()
            #expect(context.store.lastUpdated != nil)

            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "tr_TR")
            calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 41))!
            let isList = name == "goalsListMacLight"
            let size = isList ? CGSize(width: 420, height: 360) : CGSize(width: 720, height: 900)
            let store = context.store
            let root = NavigationStack {
                if isList {
                    GoalsView(store: store, selection: .constant(nil))
                } else {
                    GoalDetailView(store: store, goal: GraceDayVault.stretching, day: GraceDayVault.today)
                }
            }
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
            // The page loads its history (the list its statuses) in a `.task`: wait until the
            // index is idle and the balance is drawn from the loaded answer.
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
                testName: "graceDay",
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
#endif
