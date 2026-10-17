#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    // Local record (Mac references are not drawn in CI, see snapshot-suites.sh):
    // SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/EntityGalleryMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// "Varlık tipi ekle" at the Mac sheet's minimum size: the gallery, and the type editor pushed
    /// inside it (its bottom bar, no back arrow).
    @MainActor @Suite("Entity gallery snapshots (macOS)", .serialized)
    struct EntityGalleryMacSnapshotTests {
        @Test func galleryMacLight() async throws { try await run("galleryMacLight", opening: nil) }
        @Test func galleryEditorMacLight() async throws { try await run("galleryEditorMacLight", opening: "film") }

        private func run(_ name: String, opening id: String?) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let opening = id.flatMap { id in EntityTypeGallery.items.first { $0.definition.id == id }?.definition }
            let size = CGSize(width: InkSpacing.macSettingsMinWidth, height: 760)

            let root = NavigationStack { EntityTypeGalleryView(store: store, opening: opening) { _ in } }
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .environment(\.colorScheme, .light)
                .transaction { $0.animation = nil }
                .frame(width: size.width, height: size.height)

            MacSnapshotEnvironment.requireOverlayScrollers()
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = MacSnapshotWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }

            for _ in 0..<100 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                if !store.isProcessing { break }
            }
            try? await Task.sleep(for: .milliseconds(200))

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: name, record: record, file: #filePath, testName: "entityGallery", line: #line)
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
