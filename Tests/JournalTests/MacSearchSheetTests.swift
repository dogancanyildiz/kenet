#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// A page opened from the search results keeps a way back to them inside the sheet: the
    /// window's toolbar search is behind the sheet (review finding on the Mac layout work).
    ///
    /// Everything is mounted offscreen and nothing sends mouse events: the real click through
    /// the three page kinds is in the Mac screen tour (`13-arama-*-sonuclara-donus`).
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MacSearchSheetTests {
        private let watchdog = HostedTestWatchdog()

        enum Page: String, CaseIterable { case note, entity, day }

        /// The real sheet with a page open: the page's manşet shows the magnifier again.
        @Test(arguments: Page.allCases)
        func pageOpenedInTheSheetShowsItsSearchIcon(_ page: Page) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
            let destination: SearchDestination
            // The edit pencil of an entity page sits beside the magnifier.
            let expected: Int
            switch page {
            case .note:
                destination = .note("notes/Okuma Listesi.md")
                expected = 1
            case .entity:
                let person = try #require(context.store.content.entities.first { $0.kind == "person" })
                destination = .entity(person.id)
                expected = 2
            case .day:
                destination = .day(try #require(CalendarDate("2026-09-27")))
                expected = 1
            }
            model.path = [destination]

            let size = CGSize(width: 650, height: 650)
            let defaults = context.defaults.defaults
            let mount = HostedLayout.Mount(
                SearchView(store: context.store, model: model)
                    .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                    .environment(CalendarService(source: IdleSearchCalendarSource()))
                    .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                    .environment(IntentNavigation())
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    .frame(width: size.width, height: size.height),
                size: size)
            defer { mount.close() }
            await mount.settle(rounds: 16)
            #expect(model.path == [destination], "the page is open")
            let icons = Self.headerIcons(in: mount, width: size.width)
            #expect(icons.count >= expected, "manşet icons of the \(page.rawValue) page: \(icons)")
        }

        /// The context the sheet gives its pages: the magnifier is drawn in a manşet row and
        /// pressing it runs the sheet's "back to the results".
        @Test func sheetContextDrawsTheHeaderSearchAndItLeadsBackToTheResults() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
            model.query = "Okuma"
            model.path = [.note("notes/Okuma Listesi.md")]
            let box = ActionBox()

            let inside = HostedLayout.Mount(
                HeaderProbe(box: box).searchSheetContext { model.showResults() },
                size: CGSize(width: 640, height: 80))
            defer { inside.close() }
            await inside.settle()
            #expect(Self.headerIcons(in: inside, width: 640).count == 2, "the screen icon and search")

            let outside = HostedLayout.Mount(HeaderProbe(box: ActionBox()), size: CGSize(width: 640, height: 80))
            defer { outside.close() }
            await outside.settle()
            #expect(Self.headerIcons(in: outside, width: 640).count == 1, "outside the sheet: no search")

            let openSearch = try #require(box.openSearch, "the page reads the sheet's search action")
            #expect(box.isSearchSheet == true)
            openSearch()
            #expect(model.path.isEmpty, "search on the page leads back to the results")
            #expect(model.query == "Okuma", "the query stays")
        }

        /// Icon-sized controls at the trailing end of the page's manşet row.
        private static func headerIcons(in mount: HostedLayout.Mount, width: CGFloat) -> [CGRect] {
            guard let root = mount.window.contentView else { return [] }
            return mount.views(NSView.self)
                .filter { $0 !== root }
                .map { $0.convert($0.bounds, to: root) }
                .filter { box in
                    let top = root.isFlipped ? box.minY : root.bounds.height - box.maxY
                    return box.width >= 20 && box.width <= 44 && box.height >= 20 && box.height <= 44
                        && box.maxX > width - 130 && top < 160
                }
                .reduce(into: [CGRect]()) { unique, box in
                    if !unique.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(box) }) { unique.append(box) }
                }
        }

        @MainActor
        final class ActionBox {
            var openSearch: (@MainActor @Sendable () -> Void)?
            var isSearchSheet: Bool?
        }

        /// A manşet row as a page draws it, handing its environment to the test.
        private struct HeaderProbe: View {
            let box: ActionBox
            @Environment(\.openSearch) private var openSearch
            @Environment(\.isSearchSheet) private var isSearchSheet

            var body: some View {
                InkPageHeader(verbatim: "Okuma Listesi") {
                    InkHeaderAction("Düzenle", systemImage: "pencil", role: .primary) {}
                    SearchButton()
                }
                .frame(width: 640, alignment: .leading)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .onAppear {
                    box.openSearch = openSearch
                    box.isSearchSheet = isSearchSheet
                }
            }
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
