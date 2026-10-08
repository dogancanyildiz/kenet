#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// A page opened from the search results keeps a way back to them inside the sheet: the
    /// window's toolbar search is behind the sheet (review finding on the Mac layout work).
    @MainActor @Suite(.serialized)
    struct MacSearchSheetTests {
        enum Page: String, CaseIterable { case note, entity, day }

        @Test(arguments: Page.allCases)
        func openedPageLeadsBackToTheResults(_ page: Page) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
            let destination: SearchDestination
            switch page {
            case .note: destination = .note("notes/Okuma Listesi.md")
            case .entity:
                destination = .entity(try #require(context.store.content.entities.first { $0.kind == "person" }).id)
            case .day: destination = .day(try #require(CalendarDate("2026-09-27")))
            }
            model.path = [destination]

            let size = CGSize(width: 650, height: 650)
            let defaults = context.defaults.defaults
            let host = MacHost(
                SearchView(store: context.store, model: model)
                    .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                    .environment(CalendarService(source: IdleSearchCalendarSource()))
                    .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                    .environment(IntentNavigation())
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    .frame(width: size.width, height: size.height),
                size: size)
            defer { host.close() }
            await host.settle()
            await host.settle()
            #expect(model.path == [destination], "the page is open before the click")

            // The magnifier is the rightmost manşet icon of the page: walk in from the trailing
            // edge, down from the top, and stop at the first click that returns to the results.
            var hit: CGPoint?
            scan: for y in stride(from: CGFloat(24), through: 136, by: 8) {
                for x in stride(from: size.width - 20, through: size.width - 52, by: -8) {
                    host.click(at: CGPoint(x: x, y: y))
                    if model.path.isEmpty {
                        hit = CGPoint(x: x, y: y)
                        break scan
                    }
                }
            }
            #expect(hit != nil, "no manşet icon of the \(page.rawValue) page led back to the results")
            #expect(model.path.isEmpty)
        }

        @Test func modelReturnsToResultsAndKeepsTheQuery() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
            model.query = "Okuma"
            model.path = [.note("notes/Okuma Listesi.md")]
            model.showResults()
            #expect(model.path.isEmpty)
            #expect(model.query == "Okuma")
        }
    }

    @MainActor
    private final class IdleSearchCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
