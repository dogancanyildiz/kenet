#if os(iOS)
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Hızlı giriş, tanınan adların çipleriyle: olay ve görev kipi; açık, koyu, AX3.
    enum QuickEntryNameChipSnapshotCase: String, CaseIterable, Sendable {
        case namesEventLight
        case namesEventDark
        case namesEventAX3
        case namesTaskLight
        case namesTaskDark
        case namesTaskAX3

        var colorScheme: SnapshotColorScheme {
            self == .namesEventDark || self == .namesTaskDark ? .dark : .light
        }
        var dynamicType: SnapshotDynamicType {
            self == .namesEventAX3 || self == .namesTaskAX3 ? .accessibility3 : .medium
        }
        var isTask: Bool { [.namesTaskLight, .namesTaskDark, .namesTaskAX3].contains(self) }
    }

    @MainActor @Suite("Quick entry name chip snapshots")
    struct QuickEntryNameChipSnapshotTests {
        /// The bar alone: a person, a place and an ambiguous name as chips in the one row above
        /// the field; in task mode after the date control and the expression chips.
        @Test(arguments: QuickEntryNameChipSnapshotCase.allCases)
        func quickEntryNames(_ snapshotCase: QuickEntryNameChipSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let model = QuickEntryModel(store: store, today: { snapshotDay }, now: { snapshotNow })
            model.languages = [.turkish, .english]
            if snapshotCase.isTask {
                model.mode = .task
                model.text = "yarın Ece'yi ve Mert Aksu'yu ara"
            } else {
                model.text = "Deniz'le Çınaraltı Kafe'de, Mert Aksu da geldi"
            }
            #expect(model.recognizedNames.count == (snapshotCase.isTask ? 2 : 3))
            let location = LocationService(source: FakeLocationSource(), defaults: context.defaults.defaults)
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: store,
                size: CGSize(width: 390, height: snapshotCase.dynamicType == .medium ? 200 : 320),
                testName: "quickEntry",
                file: #filePath,
                line: #line,
                content: {
                    // Placed as on the day page; a plain stack would offer the bar half the canvas.
                    Color.ink.paper.safeAreaInset(edge: .bottom, spacing: 0) {
                        QuickEntryBar(store: store, isEnabled: true, model: model)
                            // The host centres this short canvas between unequal safe areas;
                            // keep the capsule clear of the edge that shift would cut.
                            .padding(.bottom, 16)
                    }
                    .environment(location)
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                }
            )
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

    // Local inspection only (CI records authoritative Mac references; do not commit local PNGs):
    // SNAPSHOT_MAC_LOCAL=1 SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/QuickEntryNameChipMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    @MainActor @Suite("Quick entry name chip snapshots (macOS)",
        .enabled(if: MacSnapshotEnvironment.isEnabled,
            "Mac references belong to CI; set SNAPSHOT_MAC_LOCAL=1 for local inspection (do not commit)."))
    struct QuickEntryNameChipMacSnapshotTests {
        /// The shared bar at the quick-entry panel's width and on its surface.
        @Test(arguments: ["quickEntryNamesMacLight", "quickEntryNamesMacDark"])
        func quickEntryNamesMac(_ name: String) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = context.today
            // 2026-10-03 09:41 at +03:00; the event mode's time control shows the clock.
            let now = Date(timeIntervalSince1970: 1_791_009_660)
            let model = QuickEntryModel(store: context.store, today: { day }, now: { now })
            model.languages = [.turkish, .english]
            model.text = "Deniz'le Çınaraltı Kafe'de, Mert Aksu da geldi"

            let location = LocationService(
                source: FakeLocationSource(), defaults: context.defaults.defaults)
            let size = CGSize(width: 480, height: 120)
            let root = Color.ink.surface.safeAreaInset(edge: .bottom, spacing: 0) {
                QuickEntryBar(store: context.store, isEnabled: true, model: model)
            }
            .frame(width: size.width, height: size.height)
            .environment(location)
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 3 * 3600)!)
            .environment(\.clockNow, { now })
            .environment(\.colorScheme, name == "quickEntryNamesMacDark" ? .dark : .light)

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
            for _ in 0..<20 {
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
                testName: "quickEntry",
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
