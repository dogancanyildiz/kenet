import SwiftUI
import Testing

@testable import Journal

#if os(iOS)
    import SnapshotTesting
    import UIKit

    /// The sync indicator while iCloud downloads, above the day list as the main screen places it
    /// (`ContentView`, top inset): the content stays.
    @MainActor @Suite("Sync status snapshots", .serialized, .timeLimit(.minutes(2)))
    struct SyncStatusSnapshotTests {
        @Test func downloadingLight() async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            await SnapshotHost.assertView(
                colorScheme: .light,
                dynamicType: .medium,
                increaseContrast: false,
                named: "downloadingLight",
                store: context.store,
                testName: "syncStatus"
            ) {
                SnapshotHost.hostedView(screen: .days, store: context.store, defaults: context.defaults.defaults)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        SyncStatusIndicator(status: .downloading(3))
                    }
            }
        }
    }
#endif

#if os(macOS)
    import AppKit
    import SnapshotTesting

    // Local inspection only (CI records authoritative Mac references; do not commit local PNGs):
    // SNAPSHOT_MAC_LOCAL=1 SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/SyncStatusMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// The sync indicator while iCloud downloads, at the top of a Mac window; CI owns the reference.
    @MainActor
    @Suite(
        "Sync status snapshots (macOS)",
        .enabled(
            if: MacSnapshotEnvironment.isEnabled,
            "Mac references belong to CI; set SNAPSHOT_MAC_LOCAL=1 for local inspection (do not commit)."))
    struct SyncStatusMacSnapshotTests {
        @Test func downloadingMacLight() async throws {
            let size = CGSize(width: 720, height: 160)
            let root = VStack(spacing: 0) {
                SyncStatusIndicator(status: .downloading(3))
                Spacer(minLength: 0)
            }
            .background(Color.ink.paper)
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)

            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = MacSnapshotWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            // Frame pump: SwiftUI and AppKit draw on a later run-loop turn and report no event to await.
            for _ in 0..<10 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
            }

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: "downloadingMacLight",
                record: record,
                file: #filePath,
                testName: "syncStatus",
                line: #line
            )
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
