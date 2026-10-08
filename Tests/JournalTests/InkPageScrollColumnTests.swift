#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Journal

    /// A page that is its own scroll container fills the Mac column (scroll bar on the column's
    /// edge) and holds only its content to the 680 pt reading width. Measured on the hosted
    /// layout: the AppKit scroll view SwiftUI builds and the frame a row really gets.
    @MainActor
    struct InkPageScrollColumnTests {
        private static let wide = CGSize(width: 1100, height: 700)

        private struct Measured {
            var scroll: CGRect
            var row: CGRect
            /// The vertical scroll bar, nil when the page does not overflow.
            var scroller: CGRect?
        }

        /// The page's scroll view and a full-width probe row, both in window coordinates.
        private static func measure(_ page: some View, probe: ProbeSink, size: CGSize) async throws -> Measured {
            let mount = HostedLayout.Mount(page, size: size)
            defer { mount.close() }
            await mount.settle(rounds: 10)
            let scroll = try #require(
                mount.views(NSScrollView.self).max { $0.frame.width < $1.frame.width },
                "the page has no scroll view")
            let scroller = scroll.verticalScroller.map { $0.convert($0.bounds, to: nil) }
            return Measured(
                scroll: scroll.convert(scroll.bounds, to: nil), row: probe.frame,
                scroller: scroller.flatMap { $0.height > 0 ? $0 : nil })
        }

        @Test func listFillsTheColumnAndCentersItsRows() async throws {
            let probe = ProbeSink()
            let page = List {
                ProbeRow(sink: probe)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .inkPage()
            .inkPageScrollColumn()
            let measured = try await Self.measure(page, probe: probe, size: Self.wide)
            #expect(abs(measured.scroll.minX) < 0.5, "scroll view starts at \(measured.scroll.minX)")
            #expect(
                abs(measured.scroll.width - Self.wide.width) < 0.5, "scroll view is \(measured.scroll.width) pt wide")
            // A plain Mac list insets its rows itself, a point more on the trailing side.
            #expect(abs(measured.row.midX - Self.wide.width / 2) <= 1, "row is centered on \(measured.row.midX)")
            #expect(measured.row.width <= InkSpacing.macPageWidth + 0.5, "row is \(measured.row.width) pt wide")
            // A plain Mac list insets its rows a few points on its own; the rest is the page.
            #expect(measured.row.width >= InkSpacing.macPageWidth - 40, "row is \(measured.row.width) pt wide")
        }

        @Test func scrollViewFillsTheColumnAndCentersItsContent() async throws {
            let probe = ProbeSink()
            let page = ScrollView {
                ProbeRow(sink: probe)
                Color.clear.frame(height: 2000)
            }
            .inkPage()
            .inkPageScrollColumn()
            let measured = try await Self.measure(page, probe: probe, size: Self.wide)
            #expect(
                abs(measured.scroll.width - Self.wide.width) < 0.5, "scroll view is \(measured.scroll.width) pt wide")
            #expect(abs(measured.row.midX - Self.wide.width / 2) < 0.5, "content is centered on \(measured.row.midX)")
            #expect(
                abs(measured.row.width - InkSpacing.macPageWidth) < 0.5, "content is \(measured.row.width) pt wide")
            // The scroll bar stays on the column's edge, not beside the page.
            let scroller = try #require(measured.scroller, "the page does not overflow")
            #expect(abs(scroller.maxX - Self.wide.width) < 0.5, "scroll bar ends at \(scroller.maxX)")
        }

        /// Narrower than the reading width (list column, sheet): nothing is taken from the sides.
        @Test func narrowColumnKeepsItsFullWidth() async throws {
            let probe = ProbeSink()
            let page = ScrollView {
                ProbeRow(sink: probe)
                Color.clear.frame(height: 2000)
            }
            .inkPage()
            .inkPageScrollColumn()
            let size = CGSize(width: 420, height: 600)
            let measured = try await Self.measure(page, probe: probe, size: size)
            #expect(abs(measured.scroll.width - size.width) < 0.5)
            #expect(abs(measured.row.width - size.width) < 0.5, "content is \(measured.row.width) pt wide")
        }

        /// The real detail pages, in a column wider than the page: task and entity.
        @Test func taskDetailFillsTheColumn() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let row = try #require(context.store.content.tasks.first)
            let page = TaskDetailView(store: context.store, row: row) { _ in }
                .environment(\.locale, Locale(identifier: "tr_TR"))
            try await Self.expectPage(page)
        }

        @Test func entityPageFillsTheColumn() async throws {
            let context = try EntityPageTestContext()
            defer { context.clean() }
            await context.start()
            let entity = try #require(context.store.content.entities.first { $0.id == context.path })
            let page = EntityView(store: context.store, entity: entity)
                .environment(\.locale, Locale(identifier: "tr_TR"))
            try await Self.expectPage(page)
        }

        /// The page's scroll view spans the host; every list row's content sits inside the
        /// centered reading column.
        static func expectPage(_ page: some View, minimumRows: Int = 3) async throws {
            let mount = HostedLayout.Mount(page, size: wide)
            defer { mount.close() }
            await mount.settle(rounds: 12)
            let scroll = try #require(
                mount.views(NSScrollView.self).max { $0.frame.width < $1.frame.width },
                "the page has no scroll view")
            let frame = scroll.convert(scroll.bounds, to: nil)
            #expect(abs(frame.width - wide.width) < 0.5, "scroll view is \(frame.width) pt wide")
            let table = try #require(mount.views(NSTableView.self).first, "the page is not table backed")
            #expect(table.numberOfRows >= minimumRows)
            let side = (wide.width - InkSpacing.macPageWidth) / 2
            var widest: CGFloat = 0
            for index in 0..<table.numberOfRows {
                guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) else { continue }
                let content = cell.convert(cell.bounds, to: nil)
                widest = max(widest, content.width)
                #expect(content.minX >= side - 0.5, "row \(index) starts at \(content.minX)")
                #expect(content.maxX <= wide.width - side + 0.5, "row \(index) ends at \(content.maxX)")
            }
            #expect(widest >= InkSpacing.macPageWidth - 40, "widest row is \(widest) pt")
        }
    }

    @MainActor
    private final class ProbeSink {
        var frame = CGRect.zero
    }

    private struct ProbeRow: View {
        let sink: ProbeSink

        var body: some View {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    sink.frame = $0
                }
        }
    }
#endif
