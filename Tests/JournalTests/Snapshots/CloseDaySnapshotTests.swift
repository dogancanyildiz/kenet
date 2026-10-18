#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// "Günü kapat" sheet'i: görev adımı ve hedef adımı; her biri açık temada.
    /// Separate `@Test` methods so one case can be re-recorded alone.
    @MainActor @Suite("Close day snapshots", .serialized)
    struct CloseDaySnapshotTests {
        @Test func tasksLight() async throws { try await run(.tasks, "tasksLight") }
        @Test func goalsLight() async throws { try await run(.goals, "goalsLight") }
        @Test func journalLight() async throws { try await run(.journal, "journalLight") }

        private func run(
            _ step: CloseDayStep, _ name: String, scheme: SnapshotColorScheme = .light,
            type: SnapshotDynamicType = .medium
        ) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            // Goals: the sample day with two daily goals still short of their targets.
            let day = step == .tasks ? snapshotDay : goalsSnapshotDay
            let probe = try await CloseDayModel.opened(store: store, today: day, step: step)
            let rows = try await store.computeDayTasks(on: day)
            #expect(probe.step == step)
            #expect(step == .journal ? probe.steps == [.tasks, .goals, .journal] : !probe.steps.isEmpty)
            // Goal rows are drawn disabled until the day's history is read.
            let ready = CloseDayReadyBox()
            await SnapshotHost.assertView(
                colorScheme: scheme, dynamicType: type, increaseContrast: false, named: name, store: store,
                clock: step == .tasks ? snapshotNow : goalsSnapshotNow, isReady: ready.check,
                testName: "closeDay", file: #filePath, line: #line
            ) {
                NavigationStack { CloseDayView(store: store, today: day, tasks: rows, step: step) }
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                    .onPreferenceChange(GoalsStripReadyKey.self) { ready.isReady = $0 }
            }
        }
    }

    @MainActor private final class CloseDayReadyBox {
        var isReady = false
        func check() -> Bool { isReady }
    }
#endif

#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    // Local record (Mac references are not drawn in CI, see snapshot-suites.sh):
    // SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/CloseDayMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// "Günü kapat" at the Mac sheet's ideal size: both steps, with the bottom action bar.
    @MainActor @Suite("Close day snapshots (macOS)", .serialized)
    struct CloseDayMacSnapshotTests {
        @Test func tasksMacLight() async throws { try await run(.tasks, "tasksMacLight", scheme: .light) }
        @Test func goalsMacDark() async throws { try await run(.goals, "goalsMacDark", scheme: .dark) }
        @Test func journalMacLight() async throws { try await run(.journal, "journalMacLight", scheme: .light) }
        @Test func journalMacDark() async throws { try await run(.journal, "journalMacDark", scheme: .dark) }

        private func run(_ step: CloseDayStep, _ name: String, scheme: ColorScheme) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            // The same sample days as the iPhone references.
            let day = CalendarDate(step == .tasks ? "2026-09-20" : "2026-09-17")!
            let probe = try await CloseDayModel.opened(store: store, today: day, step: step)
            let rows = try await store.computeDayTasks(on: day)
            #expect(probe.step == step)
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "tr_TR")
            calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
            let size = CGSize(width: InkSheetChrome.macIdealWidth, height: InkSheetChrome.macIdealHeight)

            let ready = MacCloseDayReadyBox()
            let root = NavigationStack { CloseDayView(store: store, today: day, tasks: rows, step: step) }
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                .environment(\.colorScheme, scheme)
                .onPreferenceChange(GoalsStripReadyKey.self) { ready.isReady = $0 }
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
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }

            for _ in 0..<100 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                if !store.isProcessing, ready.isReady { break }
            }
            #expect(ready.isReady, "goals must finish loading before the Mac reference is drawn")

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: name, record: record, file: #filePath, testName: "closeDay", line: #line)
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

    @MainActor private final class MacCloseDayReadyBox {
        var isReady = false
    }
#endif
