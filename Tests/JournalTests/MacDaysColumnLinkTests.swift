#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Journal

    /// The Günlük column's two links (Özetler, Haftalık inceleme) take a real mouse click on the
    /// Mac, also after a click on a calendar day: in a selectable `List` row they stopped taking
    /// clicks once a day button of the same list had been clicked.
    /// The window goes on screen nearly transparent for the click (`MacHost`).
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MacDaysColumnLinkTests {
        private let watchdog = HostedTestWatchdog()

        @Test func özetlerClickOpensTheSummaries() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let opened = OpenCount()
            let host = MacHost(Self.column(context: context) { opened.value += 1 }, size: Self.size)
            defer { host.close() }
            await host.settle()
            try await Self.clickCalendarDay(on: host)
            // By identifier: CI runs the process in English while the hosted view is Turkish.
            let clicked = await host.clickElement { $0.identifier == "button.summaries" }
            try #require(clicked, "no Özetler button in the column")
            await host.settle()
            #expect(opened.value == 1, "the click did not reach Özetler (\(opened.value) calls)")
        }

        @Test func weeklyReviewClickOpensItsSheet() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let host = MacHost(Self.column(context: context) {}, size: Self.size)
            defer { host.close() }
            await host.settle()
            try await Self.clickCalendarDay(on: host)
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            let clicked = await host.clickElement { $0.identifier == "button.weeklyReview" }
            try #require(clicked, "no Haftalık inceleme button in the column")
            var opened: [NSWindow] = []
            for _ in 0..<40 where opened.isEmpty && host.hostWindow.attachedSheet == nil {
                await host.settle()
                opened = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.isVisible }
            }
            #expect(
                host.hostWindow.attachedSheet != nil
                    || opened.contains { String(describing: type(of: $0)).contains("Sheet") },
                "the click did not open the weekly review: \(opened)")
            if let sheet = host.hostWindow.attachedSheet { host.hostWindow.endSheet(sheet) }
            for window in opened { window.orderOut(nil) }
        }

        /// A click on a day of the month first: in the list a link row stopped taking clicks
        /// once a calendar day button of the same list had been clicked.
        private static func clickCalendarDay(on host: MacHost) async throws {
            let clicked = await host.clickElement { $0.role == "AXButton" && $0.label.hasPrefix("15 ") }
            try #require(clicked, "no calendar day 15 in the column")
            await host.settle()
        }

        private static let size = CGSize(width: InkSpacing.macListIdealWidth, height: InkSpacing.macWindowMinHeight)

        private static func column(context: TaskTestContext, openSummaries: @escaping () -> Void) -> some View {
            let defaults = context.defaults.defaults
            return DaysColumnHarness(store: context.store, openSummaries: openSummaries)
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: LinkTestCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .inkPage()
        }
    }

    /// The column with a selection it owns, as in the window (a day picked in the list).
    private struct DaysColumnHarness: View {
        let store: IndexStore
        let openSummaries: () -> Void
        @State private var selection: String? = "journal/2026-09-25.md"

        var body: some View {
            MacDaysColumn(store: store, selection: $selection, openSummaries: openSummaries)
        }
    }

    @MainActor private final class OpenCount {
        var value = 0
    }

    @MainActor private final class LinkTestCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
