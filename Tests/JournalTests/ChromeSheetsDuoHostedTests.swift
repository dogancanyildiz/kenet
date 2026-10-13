#if os(iOS)
    import Testing
    import UIKit

    @testable import Journal

    /// Runs with the normal unit suite as well as the opt-in Duo image suite.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(2)))
    struct ChromeSheetsDuoHostedTests {
        /// Today in the split shell: the manşet row (title, gear, magnifier) is the page's only
        /// bar, as on the phone. The sidebar button sits in the list column's bar beside it, so
        /// the detail column shows no empty system bar above the manşet.
        @Test func todayKeepsTheManşetAsItsOnlyBar() async throws {
            try await ChromeSheetsDuoHost.withWindow(.today) { _, host in
                let split = try #require(
                    AdaptiveShellHostedTests.Shell.controllers(of: UISplitViewController.self, under: host).first)
                let detail = try #require(split.viewController(for: .secondary))
                let detailBar = try #require(
                    AdaptiveShellHostedTests.Shell.controllers(of: UINavigationController.self, under: detail).first)
                #expect(detailBar.isNavigationBarHidden, "Today's system bar must stay hidden in the split shell.")
                let list = try #require(split.viewController(for: .supplementary))
                let listBar = try #require(
                    AdaptiveShellHostedTests.Shell.controllers(of: UINavigationController.self, under: list).first)
                #expect(!listBar.isNavigationBarHidden, "The list column's bar holds the sidebar button.")
            }
        }

        @Test func kanbanKeepsItsDetailPanelBesideTheBoard() async throws {
            try await ChromeSheetsDuoHost.withWindow(.kanbanPanel) { window, host in
                #expect(host.presentedViewController == nil, "890 pt uses the inline detail panel.")
                let panel = try #require(
                    ChromeSheetsDuoHost.views(UICollectionView.self, under: host.view).first { list in
                        let frame = list.convert(list.bounds, to: window)
                        return abs(frame.width - 340) <= 2 && frame.minX > 500
                    },
                    "The 340 pt task detail must be beside the board, inside the canvas.")
                let frame = panel.convert(panel.bounds, to: window)
                #expect(frame.maxX <= window.bounds.maxX + 1)
                #expect(!panel.visibleCells.isEmpty)
            }
        }

        /// Each sheet opens the way it does in production: Settings through `SplitShell`, the
        /// task through `KanbanView`'s sheet, closing the day through the reminder route.
        @Test(arguments: [
            ChromeSheetsDuoCase.settings, .search, .taskDetail, .closeDay,
        ])
        func formSheetHasVisibleContent(_ screen: ChromeSheetsDuoCase) async throws {
            try await ChromeSheetsDuoHost.withWindow(screen) { _, host in
                let sheet = try #require(host.presentedViewController, "The form sheet never opened.")
                #expect(sheet.view.bounds.height >= 360)
                if screen.usesFormSizing {
                    // The plain system sheet of the regular width is 414 pt; the form is wider.
                    #expect(sheet.view.bounds.width >= 480, "\(screen) is not presented as a form sheet.")
                }
                #expect(
                    ChromeSheetsDuoHost.hasVisibleRowOrField(in: sheet.view),
                    "A title bar alone is not a usable sheet.")
            }
        }
    }
#endif
