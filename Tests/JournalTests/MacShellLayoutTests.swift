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
            #expect(abs(widths[0] - 200) <= 2, "sidebar \(widths[0]) pt")
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
            let split = try #require(
                mount.views(NSSplitView.self).first { $0.arrangedSubviews.count == 3 },
                "split views: \(mount.views(NSSplitView.self).map { $0.arrangedSubviews.count })")
            // The sidebar floats over the leading edge of the list pane, so the pane's frame starts
            // under it: the visible list column is what is left of the pane beside the sidebar.
            let panes = split.arrangedSubviews.map(\.frame)
            return [panes[0].width, panes[1].maxX - panes[0].maxX, panes[2].width]
        }
    }
#endif
