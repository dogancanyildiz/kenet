#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Journal

    /// Column widths and the smallest window, measured on a real split view (audit findings 2, 3).
    @MainActor
    struct MacShellLayoutTests {
        private struct Columns: View {
            var body: some View {
                NavigationSplitView {
                    List { Text(verbatim: "Zaman çizelgesi") }.macSidebarColumn()
                } content: {
                    Text(verbatim: "liste").frame(maxWidth: .infinity, maxHeight: .infinity).macListColumn()
                } detail: {
                    Text(verbatim: "ayrıntı").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .macMainWindowMinimumSize()
            }
        }

        /// 1280 pt, the window the tour and the audit used: 200 + 320 and the page still fits.
        @Test func columnsOpenAtTheirIdealWidths() async throws {
            let widths = try await columnWidths(window: 1280)
            try await MacSplitMeasure.expectSidebar(widths[0], isIdeal: 200, window: 1280)
            #expect(abs(widths[1] - 320) <= 2, "list \(widths[1]) pt")
            #expect(widths[2] >= InkSpacing.macPageWidth, "detail \(widths[2]) pt holds the 680 pt page")
        }

        /// The smallest window keeps every column at or above its minimum.
        @Test func smallestWindowKeepsEveryColumnUsable() async throws {
            let widths = try await columnWidths(window: InkSpacing.macWindowMinWidth)
            #expect(widths[0] >= InkSpacing.macSidebarMinWidth - 1, "sidebar \(widths[0]) pt")
            #expect(widths[0] <= InkSpacing.macSidebarMaxWidth + 1)
            #expect(widths[1] >= InkSpacing.macListMinWidth - 1, "list \(widths[1]) pt")
            #expect(widths[1] <= InkSpacing.macListMaxWidth + 1)
            #expect(widths[2] >= 440, "detail \(widths[2]) pt")
        }

        @Test func windowDoesNotShrinkBelowItsMinimum() {
            let controller = NSHostingController(rootView: Columns())
            let fitted = controller.sizeThatFits(in: CGSize(width: 500, height: 300))
            #expect(fitted.width == InkSpacing.macWindowMinWidth, "width \(fitted.width)")
            #expect(fitted.height == InkSpacing.macWindowMinHeight, "height \(fitted.height)")
            #expect(InkSpacing.macWindowMinWidth == 1000)
            #expect(
                InkSpacing.macWindowMinWidth
                    >= InkSpacing.macSidebarIdealWidth + InkSpacing.macListMinWidth + 500,
                "room for sidebar, the narrowest list and a 500 pt detail")
        }

        private func columnWidths(window width: CGFloat) async throws -> [CGFloat] {
            let mount = HostedLayout.Mount(Columns(), size: CGSize(width: width, height: 700))
            defer { mount.close() }
            await mount.settle(rounds: 12)
            return try MacSplitMeasure.columns(in: mount)
        }
    }

    /// Reads the three columns of a hosted split view, and compares a sidebar with reference
    /// sidebars of a known width.
    @MainActor
    enum MacSplitMeasure {
        /// Sidebar, visible list column and detail of the first three-pane split under the mount.
        static func columns(in mount: HostedLayout.Mount) throws -> [CGFloat] {
            let split = try #require(
                mount.views(NSSplitView.self).first { $0.arrangedSubviews.count == 3 },
                "split views: \(mount.views(NSSplitView.self).map { $0.arrangedSubviews.count })")
            // Where the sidebar floats over the leading edge of the list pane (macOS 27), the
            // pane's frame starts under it: the visible list column is what is left of the pane
            // beside the sidebar. Where the panes sit side by side the same difference holds.
            let panes = split.arrangedSubviews.map(\.frame)
            return [panes[0].width, panes[1].maxX - panes[0].maxX, panes[2].width]
        }

        /// The system may draw a sidebar column wider than it was asked to (macOS 26 measured
        /// 208 pt for 200). So the sidebar is compared with two reference sidebars fixed at the
        /// limits of the spec, 180 and 240 pt, hosted the same way: whatever the system adds,
        /// the ideal lies `ideal - 180` above the narrow one and `240 - ideal` below the wide one.
        static func expectSidebar(_ measured: CGFloat, isIdeal ideal: CGFloat, window: CGFloat) async throws {
            let narrow = try await sidebarWidth(fixedAt: 180, window: window)
            let wide = try await sidebarWidth(fixedAt: 240, window: window)
            #expect(
                abs((wide - narrow) - 60) <= 1,
                "references: 180 pt drew \(narrow) pt, 240 pt drew \(wide) pt; the system allowance is not constant")
            #expect(
                abs((measured - narrow) - (ideal - 180)) <= 1,
                "sidebar \(measured) pt; a 180 pt sidebar draws \(narrow) pt, so \(ideal) pt draws \(narrow + ideal - 180) pt"
            )
            #expect(
                abs((wide - measured) - (240 - ideal)) <= 1,
                "sidebar \(measured) pt; a 240 pt sidebar draws \(wide) pt")
        }

        private struct Reference: View {
            let sidebar: CGFloat

            var body: some View {
                NavigationSplitView {
                    List { Text(verbatim: "Zaman çizelgesi") }.navigationSplitViewColumnWidth(sidebar)
                } content: {
                    Text(verbatim: "liste").frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
                } detail: {
                    Text(verbatim: "ayrıntı").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }

        private static func sidebarWidth(fixedAt width: CGFloat, window: CGFloat) async throws -> CGFloat {
            let mount = HostedLayout.Mount(Reference(sidebar: width), size: CGSize(width: window, height: 700))
            defer { mount.close() }
            await mount.settle(rounds: 12)
            return try columns(in: mount)[0]
        }
    }
#endif
