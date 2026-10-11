#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Haftalık inceleme sheet'i: her adım açık temada; ilk adım ve önizleme ayrıca koyu ve AX3.
    /// Separate `@Test` methods so one case can be re-recorded alone.
    @MainActor @Suite("Weekly review snapshots", .serialized)
    struct WeeklyReviewSnapshotTests {
        @Test func numbersLight() async throws { try await run(.numbers, "numbersLight") }
        @Test func numbersDark() async throws { try await run(.numbers, "numbersDark", scheme: .dark) }
        @Test func numbersAX3() async throws { try await run(.numbers, "numbersAX3", type: .accessibility3) }
        @Test func tasksLight() async throws { try await run(.tasks, "tasksLight") }
        @Test func peopleLight() async throws { try await run(.people, "peopleLight") }
        @Test func goalsLight() async throws { try await run(.goals, "goalsLight") }
        @Test func noteLight() async throws { try await run(.note, "noteLight") }
        @Test func previewLight() async throws { try await run(.preview, "previewLight") }
        @Test func previewDark() async throws { try await run(.preview, "previewDark", scheme: .dark) }
        @Test func previewAX3() async throws { try await run(.preview, "previewAX3", type: .accessibility3) }

        private func run(
            _ step: WeeklyReviewStep, _ name: String, scheme: SnapshotColorScheme = .light,
            type: SnapshotDynamicType = .medium
        ) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let defaults = context.defaults.defaults
            // The sample people were all seen within the default 30 days of the snapshot day.
            defaults.set(3, forKey: PeopleInsightsPreference.key)
            let calendar = weeklyReviewSnapshotCalendar(timeZone: snapshotTimeZone)
            let probe = WeeklyReviewModel(
                store: store, today: snapshotDay, calendar: calendar, locale: snapshotLocale, defaults: defaults)
            await probe.load()
            // Every drawn step has something to show.
            #expect(WeeklyReviewSection.allCases.allSatisfy { !probe.lines(for: $0).isEmpty })

            let ready = WeeklyReviewReadyBox()
            await SnapshotHost.assertView(
                colorScheme: scheme, dynamicType: type, increaseContrast: false, named: name, store: store,
                isReady: ready.check, testName: "weeklyReview", file: #filePath, line: #line
            ) {
                NavigationStack {
                    WeeklyReviewView(
                        store: store, today: snapshotDay, calendar: calendar, locale: snapshotLocale,
                        defaults: defaults, step: step, note: weeklyReviewSnapshotNote(for: step))
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .onPreferenceChange(WeeklyReviewReadyKey.self) { ready.isReady = $0 }
            }
        }
    }

    @MainActor private final class WeeklyReviewReadyBox {
        var isReady = false
        func check() -> Bool { isReady }
    }
#endif

/// A Monday week, as on a Turkish device.
func weeklyReviewSnapshotCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "tr_TR")
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    return calendar
}

/// The note and the preview are drawn with a note typed.
@MainActor func weeklyReviewSnapshotNote(for step: WeeklyReviewStep) -> String {
    step == .note || step == .preview ? "Sakin bir haftaydı.\nGelecek hafta yürüyüşleri sabaha alacağım." : ""
}

#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    // Local record (Mac references are not drawn in CI, see snapshot-suites.sh):
    // SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/WeeklyReviewMacSnapshotTests CODE_SIGNING_ALLOWED=NO

    /// The weekly review at the Mac sheet's ideal size: the first step and the preview, with the
    /// bottom action bar.
    @MainActor @Suite("Weekly review snapshots (macOS)", .serialized)
    struct WeeklyReviewMacSnapshotTests {
        @Test func numbersMacLight() async throws { try await run(.numbers, "numbersMacLight", scheme: .light) }
        @Test func previewMacDark() async throws { try await run(.preview, "previewMacDark", scheme: .dark) }

        private func run(_ step: WeeklyReviewStep, _ name: String, scheme: ColorScheme) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let defaults = context.defaults.defaults
            defaults.set(3, forKey: PeopleInsightsPreference.key)
            // The same sample day as the iPhone references.
            let day = CalendarDate("2026-09-20")!
            let locale = Locale(identifier: "tr_TR")
            let calendar = weeklyReviewSnapshotCalendar(timeZone: TimeZone(secondsFromGMT: 3 * 3600)!)
            let size = CGSize(width: InkSheetChrome.macIdealWidth, height: InkSheetChrome.macIdealHeight)

            let ready = MacWeeklyReviewReadyBox()
            let root = NavigationStack {
                WeeklyReviewView(
                    store: store, today: day, calendar: calendar, locale: locale, defaults: defaults,
                    step: step, note: weeklyReviewSnapshotNote(for: step))
            }
            .environment(\.locale, locale)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.colorScheme, scheme)
            .onPreferenceChange(WeeklyReviewReadyKey.self) { ready.isReady = $0 }
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
            #expect(ready.isReady, "the week must be read before the Mac reference is drawn")

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: Self.render(host, scale: MacSnapshotWindow.scale),
                as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: name, record: record, file: #filePath, testName: "weeklyReview", line: #line)
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

    @MainActor private final class MacWeeklyReviewReadyBox {
        var isReady = false
    }
#endif
