#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    // Local inspection only (CI records authoritative Mac references; do not commit local PNGs):
    // SNAPSHOT_MAC_LOCAL=1 SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/EntityRelationsMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// Relations section and creation sheet in the Mac detail column; CI owns references.
    @MainActor
    @Suite(
        "Entity relations snapshots (macOS)",
        .enabled(
            if: MacSnapshotEnvironment.isEnabled,
            "Mac references belong to CI; set SNAPSHOT_MAC_LOCAL=1 for local inspection (do not commit)."))
    struct EntityRelationsMacSnapshotTests {
        @Test(arguments: ["sectionMacLight", "sheetMacLight"])
        func relationsMac(_ name: String) async throws {
            let context = try await EntityRelationsModelTests.context()
            defer { context.clean() }
            let model = EntityRelationsModel(store: context.store, path: EntityRelationsModelTests.person)
            await model.load()
            #expect(model.rows.count == 4)
            let size = CGSize(width: 720, height: 900)
            let root = Group {
                if name == "sheetMacLight" {
                    EntityRelationSheet(model: model)
                } else {
                    NavigationStack {
                        List { EntityRelationsSection(model: model) }
                            .listStyle(.plain).inkPage().inkPageScrollColumn()
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "tr_TR"))
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
                testName: "relations",
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
