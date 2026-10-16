import Summaries
import VaultFormat

/// One drawn period of the synthetic vault (``SummarySyntheticVault``), on its "today" 11 October 2026.
struct SummariesSnapshotShot: Sendable {
    let period: SummaryPeriod
    let day: CalendarDate
    var today = SummarySyntheticVault.today

    /// 5–11 October 2026: ends on today, so it is compared with the whole week before.
    static let week = Self(period: .week, day: SummarySyntheticVault.today)
    static let month = Self(period: .month, day: CalendarDate("2026-09-15")!)
    /// 2026 up to 11 October: still running, so it is compared up to 11 October 2025.
    static let year = Self(period: .year, day: SummarySyntheticVault.today)
    /// 10–16 August 2026: nothing written, open tasks carried in.
    static let empty = Self(period: .week, day: CalendarDate("2026-08-12")!)
    /// 5–11 October 2026 on Thursday 8 October: Friday to Sunday have not come, so their files do not count.
    static let runningWeek = Self(
        period: .week, day: CalendarDate("2026-10-08")!, today: CalendarDate("2026-10-08")!)
}

#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Journal

    /// Özetler on the synthetic vault, whole page: week, month, year, empty week; dark and AX3.
    /// Separate `@Test` methods so one case can be re-recorded alone.
    @MainActor @Suite("Summaries snapshots", .serialized)
    struct SummariesSnapshotTests {
        @Test func weekLight() async throws { try await run(.week, "weekLight", height: 2200) }
        @Test func weekDark() async throws { try await run(.week, "weekDark", height: 2200, scheme: .dark) }
        @Test func weekAX3() async throws {
            try await run(.week, "weekAX3", height: 5600, type: .accessibility3)
        }
        @Test func monthLight() async throws { try await run(.month, "monthLight", height: 2300) }
        @Test func yearLight() async throws { try await run(.year, "yearLight", height: 2700) }
        @Test func yearDark() async throws { try await run(.year, "yearDark", height: 2700, scheme: .dark) }
        @Test func emptyLight() async throws { try await run(.empty, "emptyLight", height: 844) }
        @Test func runningWeekLight() async throws { try await run(.runningWeek, "runningWeekLight", height: 2200) }

        private func run(
            _ shot: SummariesSnapshotShot, _ name: String, height: CGFloat, scheme: SnapshotColorScheme = .light,
            type: SnapshotDynamicType = .medium
        ) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            try SummarySyntheticVault.generate(at: context.root)
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let store = context.store
            let ready = SummariesReadyBox()
            await SnapshotHost.assertView(
                colorScheme: scheme, dynamicType: type, increaseContrast: false, named: name, store: store,
                size: CGSize(width: snapshotCanvasSize.width, height: height), isReady: ready.check,
                testName: "summaries", file: #filePath, line: #line
            ) {
                NavigationStack {
                    SummariesView(
                        store: store, today: { shot.today }, period: shot.period, day: shot.day)
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.openSearch, {})
                .onPreferenceChange(SummariesReadyKey.self) { ready.isReady = $0 }
            }
        }
    }

    @MainActor private final class SummariesReadyBox {
        var isReady = false
        func check() -> Bool { isReady }
    }
#endif

#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Journal

    // Local record (Mac references are not drawn in CI, see snapshot-suites.sh):
    // SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/SummariesMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// Özetler in a 1000 pt detail area: rhythm, numbers and goals left; people, places and tasks right.
    @MainActor @Suite("Summaries snapshots (macOS)", .serialized)
    struct SummariesMacSnapshotTests {
        @Test func weekMacLight() async throws { try await run(.week, "weekMacLight", scheme: .light) }
        @Test func monthMacDark() async throws { try await run(.month, "monthMacDark", scheme: .dark) }
        @Test func yearMacLight() async throws { try await run(.year, "yearMacLight", scheme: .light) }

        private func run(_ shot: SummariesSnapshotShot, _ name: String, scheme: ColorScheme) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            try SummarySyntheticVault.generate(at: context.root)
            await context.start()
            let store = context.store
            let locale = Locale(identifier: "tr_TR")
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
            let size = CGSize(width: 1000, height: 1150)

            let ready = MacSummariesReadyBox()
            let root = NavigationStack {
                SummariesView(store: store, today: { shot.today }, period: shot.period, day: shot.day)
            }
            .environment(\.locale, locale)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.colorScheme, scheme)
            .environment(\.openSearch, {})
            .onPreferenceChange(SummariesReadyKey.self) { ready.isReady = $0 }
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

            var idle = 0
            for _ in 0..<200 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                idle = !store.isProcessing && ready.isReady ? idle + 1 : 0
                if idle >= 6 { break }
            }
            #expect(ready.isReady, "the period must be read before the Mac reference is drawn")

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: name, record: record, file: #filePath, testName: "summaries", line: #line)
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

    @MainActor private final class MacSummariesReadyBox {
        var isReady = false
    }
#endif
