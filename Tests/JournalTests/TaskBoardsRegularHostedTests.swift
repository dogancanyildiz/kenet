#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Kanban and Zaman çizelgesi in the split shell on an iPad 13" in landscape (1376 × 1032 pt,
    /// regular × regular): the detail column beside the widest Mac sidebar draws the desktop
    /// board and chart, as the Mac window does.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(2)))
    struct TaskBoardsRegularHostedTests {
        static let canvas = CGSize(width: 1376, height: 1032)
        /// The board's column: the canvas less the widest sidebar.
        static let detailWidth = canvas.width - InkSpacing.macSidebarMaxWidth

        /// Three status columns share the board beside the 340 pt panel and are all on screen;
        /// the detail is the panel, not a sheet. The panel hides no bar: the column keeps the
        /// shell's bar (sidebar button), so the manşet stays where it is with the panel closed.
        @Test func kanbanShowsThreeColumnsBesideTheDetailPanel() async throws {
            try await Self.hosted(.split, board: .kanban) { hosted in
                let (window, host, widths) = (hosted.window, hosted.host, hosted.widths.values)
                #expect(widths.count == 3, "columns \(widths)")
                let board = Self.detailWidth - KanbanDetailPlacement.panelWidth
                let used =
                    widths.reduce(0, +) + KanbanBoardLayout.columnSpacing * 2 + KanbanBoardLayout.boardPadding * 2
                #expect(widths.allSatisfy { $0 >= KanbanBoardLayout.minimumColumnWidth }, "\(widths)")
                #expect(used <= board, "columns \(widths) use \(used) of \(board)")
                #expect(host.presentedViewController == nil, "the detail opened a sheet")
                let panel = Self.views(UICollectionView.self, under: host.view).first { list in
                    let frame = list.convert(list.bounds, to: window)
                    return abs(frame.width - KanbanDetailPlacement.panelWidth) <= 2
                        && frame.maxX >= Self.detailWidth - 2
                }
                #expect(panel != nil, "no 340 pt task detail at the trailing edge")
                #expect(panel.map { !$0.visibleCells.isEmpty } ?? false, "the panel has no rows")
                let stack = try #require(Self.navigationController(under: host), "no navigation stack")
                #expect(!stack.isNavigationBarHidden, "the open panel hid the column's bar")
            }
        }

        /// The desktop board's "Grupla" menu hugs its label: a stretched label is a row-wide
        /// target, and on Mac it opens a window-wide menu.
        @Test func desktopGroupingMenuHugsItsLabel() async throws {
            try await Self.hosted(.split, board: .kanban, selects: false) { hosted in
                let menu = try #require(Self.groupingMenu(in: hosted))
                #expect(menu.width > 0 && menu.width < Self.detailWidth / 3, "the menu is \(menu.width) pt wide")
            }
        }

        /// The tab shell keeps the phone board on the full iPad width (where the desktop board's
        /// three columns would be 440 pt): one 360 pt column per page, the row-wide "Grupla" menu
        /// and the detail in a sheet.
        @Test func tabShellKeepsThePhoneBoard() async throws {
            let width = Self.canvas.width
            let desktop = KanbanBoardStyle.desktop.columnWidth(fitting: width, columns: 3)
            #expect(
                abs(desktop - KanbanBoardLayout.maximumPhoneColumnWidth) > 40, "the canvas does not tell them apart")
            try await Self.hosted(.tabs, board: .kanban, width: width) { hosted in
                let widths = hosted.widths.values
                #expect(widths.count == 3, "columns \(widths)")
                #expect(widths.allSatisfy { $0 == KanbanBoardLayout.maximumPhoneColumnWidth }, "\(widths)")
                #expect(hosted.host.presentedViewController != nil, "the phone board opens the detail in a sheet")
                let menu = try #require(Self.groupingMenu(in: hosted))
                #expect(menu.width > width / 2, "the menu is \(menu.width) pt wide")
            }
        }

        /// The chart is drawn: a horizontal scroller wider than the screen (the whole day range)
        /// and no day list.
        @Test func timelineDrawsTheChart() async throws {
            try await Self.hosted(.split, board: .timeline) { hosted in
                #expect(
                    Self.views(UICollectionView.self, under: hosted.host.view).isEmpty, "the phone day list is drawn")
                #expect(Self.chart(in: hosted) != nil, "no chart wider than the window")
            }
        }

        /// Narrowing the column past the panel threshold (the detail moves to a sheet) keeps the
        /// chart and the board: the same scroller, not one built again (back at its first day).
        @Test func panelThresholdKeepsTheChartAndTheBoard() async throws {
            try await Self.hosted(.split, board: .timeline, selects: false) { hosted in
                let chart = try #require(Self.chart(in: hosted))
                await hosted.resize(
                    width: TimelineDetailPlacement.panelWidth + TimelineDetailPlacement.minimumChartWidth - 60)
                let narrow = Self.chart(in: hosted)
                #expect(narrow === chart, "the chart was built again")
            }
            try await Self.hosted(.split, board: .kanban, selects: false) { hosted in
                let board = try #require(Self.board(in: hosted))
                await hosted.resize(
                    width: KanbanDetailPlacement.panelWidth + KanbanDetailPlacement.minimumBoardWidth - 60)
                #expect(Self.board(in: hosted) === board, "the board was built again")
            }
        }

        @Test func timelineTabShellKeepsTheDayList() async throws {
            try await Self.hosted(.tabs, board: .timeline) { hosted in
                #expect(!Self.views(UICollectionView.self, under: hosted.host.view).isEmpty, "no day list")
            }
        }

        enum Board { case kanban, timeline }

        final class Widths { var values: [CGFloat] = [] }

        @MainActor struct Hosted {
            let window: UIWindow
            let host: UIHostingController<AnyView>
            let widths: Widths

            /// Gives the column a new width and waits until the page has drawn it.
            func resize(width: CGFloat) async {
                window.frame.size.width = width
                for _ in 0..<12 {
                    // Frame pump: SwiftUI and UIKit draw on a later run-loop turn and report no event to await.
                    try? await Task.sleep(for: .milliseconds(50))
                    host.view.layoutIfNeeded()
                }
            }
        }

        /// The previous case's window, released only once the next case has its own: a window
        /// freed right after a sheet's dismissal crashed the host (see `ChromeSheetsDuoHost`).
        private static var retired: UIWindow?

        private static func hosted(
            _ shell: ShellKind, board: Board, width: CGFloat = detailWidth, selects: Bool = true,
            _ body: @MainActor (Hosted) async throws -> Void
        ) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let row = try #require(try await store.allTasks().first { !$0.isClosed && $0.rawStatus == " " })
            let tasks = TasksModel(store: store, today: { snapshotDay })
            let widths = Widths()
            let page = NavigationStack {
                Group {
                    switch board {
                    case .kanban: KanbanView(tasks: tasks, showsFilters: true, selection: selects ? row : nil)
                    case .timeline: TaskTimelineView(tasks: tasks, showsFilters: true)
                    }
                }
                .onPreferenceChange(KanbanColumnWidthPreference.self) { values in
                    MainActor.assumeIsolated { widths.values = values }
                }
            }
            .environment(\.shellKind, shell)
            .environment(\.locale, snapshotLocale)
            .environment(\.openSearch, {})
            .transaction { $0.animation = nil }
            var failure: (any Error)?
            await SnapshotHostGate.exclusive {
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                else {
                    Issue.record("The board needs the Journal test host's window scene.")
                    return
                }
                let animated = UIView.areAnimationsEnabled
                UIView.setAnimationsEnabled(false)
                defer { UIView.setAnimationsEnabled(animated) }
                let host = UIHostingController(rootView: AnyView(page))
                host.traitOverrides.horizontalSizeClass = .regular
                host.traitOverrides.verticalSizeClass = .regular
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: CGSize(width: width, height: canvas.height))
                window.rootViewController = host
                window.isHidden = false
                var idle = 0
                for _ in 0..<80 where idle < 8 {
                    // Frame pump: SwiftUI and UIKit draw on a later run-loop turn and report no event to await.
                    try? await Task.sleep(for: .milliseconds(50))
                    host.view.layoutIfNeeded()
                    let drawn = board == .timeline || !widths.values.isEmpty
                    idle = !store.isProcessing && drawn ? idle + 1 : 0
                }
                do { try await body(Hosted(window: window, host: host, widths: widths)) } catch { failure = error }
                host.presentedViewController?.dismiss(animated: false)
                // Frames for UIKit to dispose the last transition before the window is released; no event marks it.
                for _ in 0..<4 { try? await Task.sleep(for: .milliseconds(50)) }
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
                retired = window
            }
            if let failure { throw failure }
        }

        /// The chart's day axis: the scroller wider than the window that is not a list.
        private static func chart(in hosted: Hosted) -> UIScrollView? {
            views(UIScrollView.self, under: hosted.host.view).first {
                !($0 is UICollectionView) && $0.contentSize.width > hosted.window.bounds.width
            }
        }

        /// The board's horizontal scroller: the widest scroller that is not a list.
        private static func board(in hosted: Hosted) -> UIScrollView? {
            views(UIScrollView.self, under: hosted.host.view).filter { !($0 is UICollectionView) }
                .max { $0.contentSize.width < $1.contentSize.width }
        }

        /// The outermost navigation controller: the page's stack, whose bar is the column's.
        private static func navigationController(under root: UIViewController) -> UINavigationController? {
            if let stack = root as? UINavigationController { return stack }
            for child in root.children {
                if let stack = navigationController(under: child) { return stack }
            }
            return nil
        }

        /// The "Grupla" menu's frame: of the buttons that open a menu, the one at the page's
        /// leading margin (the manşet's menus sit at the trailing edge).
        private static func groupingMenu(in hosted: Hosted) -> CGRect? {
            views(UIControl.self, under: hosted.host.view)
                .filter {
                    $0.interactions.contains { String(describing: type(of: $0)).contains("ContextMenuInteraction") }
                }
                .map { $0.convert($0.bounds, to: hosted.window) }
                .min { $0.minX < $1.minX }
        }

        private static func views<T: UIView>(_ type: T.Type, under root: UIView) -> [T] {
            ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { views(type, under: $0) }
        }
    }
    extension TaskBoardsRegularHostedTests {
        /// Full iPad canvases with the observed 240 pt sidebar. Activate the card's real
        /// accessibility button, then inspect the presentation and actual column frames.
        @Test func portraitKanbanOpensSelectedCardInSheet() async throws {
            try await Self.hostedKanban(canvas: CGSize(width: 1032, height: 1376), selecting: true) { hosted in
                await Self.settleDetail(in: hosted)
                #expect(hosted.host.presentedViewController != nil, "portrait detail did not open a sheet")
                #expect(Self.detailPanel(in: hosted) == nil, "portrait kept the narrow inline panel")
            }
        }

        @Test func landscapeKanbanKeepsTwoCompleteColumnsBesideSelectedCard() async throws {
            try await Self.hostedKanban(canvas: Self.canvas, selecting: true) { hosted in
                await Self.settleDetail(in: hosted)
                #expect(hosted.host.presentedViewController == nil, "landscape detail opened a sheet")
                let panel = try #require(Self.detailPanel(in: hosted), "no inline detail panel")
                let board = try #require(Self.board(in: hosted))
                let columns = Self.views(UIScrollView.self, under: board)
                    .filter { $0 !== board && !($0 is UICollectionView) }
                    .map { $0.convert($0.bounds, to: hosted.window) }
                    .filter { $0.width >= KanbanBoardLayout.minimumColumnWidth - 1 }
                    .sorted { $0.minX < $1.minX }
                #expect(columns.count == 3, "column frames: \(columns)")
                for column in columns.prefix(2) {
                    #expect(column.minX >= board.convert(board.bounds, to: hosted.window).minX)
                    #expect(column.maxX <= panel.minX, "column \(column) clipped by panel \(panel)")
                }
            }
        }

        @Test func narrowingSelectedKanbanMovesPanelToSheetAndKeepsSelection() async throws {
            try await Self.hostedKanban(canvas: Self.canvas, selecting: true) { hosted in
                await Self.settleDetail(in: hosted)
                #expect(Self.detailPanel(in: hosted) != nil)
                let board = try #require(Self.board(in: hosted))
                await hosted.resize(width: 1032)
                await Self.settleDetail(in: hosted)
                #expect(Self.board(in: hosted) === board, "resizing rebuilt the board")
                #expect(Self.detailPanel(in: hosted) == nil)
                let sheet = try #require(hosted.host.presentedViewController, "selection lost on narrowing")
                #expect(ChromeSheetsDuoHost.hasVisibleRowOrField(in: sheet.view), "selected detail is empty")
                await hosted.resize(width: Self.canvas.width)
                await Self.settleDetail(in: hosted)
                #expect(hosted.host.presentedViewController == nil)
                #expect(Self.detailPanel(in: hosted) != nil, "selection lost when returning to the panel")
            }
        }

        private static func detailPanel(in hosted: Hosted) -> CGRect? {
            views(UICollectionView.self, under: hosted.host.view)
                .map { $0.convert($0.bounds, to: hosted.window) }
                .first {
                    abs($0.width - KanbanDetailPlacement.panelWidth) <= 2
                        && abs($0.maxX - hosted.window.bounds.maxX) <= 2
                }
        }

        private static func settleDetail(in hosted: Hosted) async {
            for _ in 0..<12 {
                // Frame pump: SwiftUI and UIKit draw on a later run-loop turn and report no event to await.
                try? await Task.sleep(for: .milliseconds(50))
                hosted.host.view.layoutIfNeeded()
                hosted.host.presentedViewController?.view.layoutIfNeeded()
            }
        }

        private static func hostedKanban(
            canvas: CGSize, selecting: Bool = false, _ body: @MainActor (Hosted) async throws -> Void
        ) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let tasks = TasksModel(store: context.store, today: { snapshotDay })
            // The selected card comes in as the board's selection, as the Pad snapshot does.
            let selection =
                selecting ? try await context.store.allTasks().first { !$0.isClosed && $0.rawStatus == " " } : nil
            let widths = Widths()
            let page = HStack(spacing: 0) {
                Color.clear.frame(width: 240)
                NavigationStack { KanbanView(tasks: tasks, showsFilters: true, selection: selection) }
            }
            .onPreferenceChange(KanbanColumnWidthPreference.self) { values in
                MainActor.assumeIsolated { widths.values = values }
            }
            .environment(\.shellKind, .split)
            .environment(\.locale, snapshotLocale)
            .environment(\.openSearch, {})
            .transaction { $0.animation = nil }
            var failure: (any Error)?
            await SnapshotHostGate.exclusive {
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                else {
                    Issue.record("The board needs the Journal test host's window scene.")
                    return
                }
                let animated = UIView.areAnimationsEnabled
                UIView.setAnimationsEnabled(false)
                defer { UIView.setAnimationsEnabled(animated) }
                let host = UIHostingController(rootView: AnyView(page))
                host.traitOverrides.horizontalSizeClass = .regular
                host.traitOverrides.verticalSizeClass = .regular
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: canvas)
                window.rootViewController = host
                window.makeKeyAndVisible()
                var idle = 0
                for _ in 0..<80 where idle < 8 {
                    // Frame pump: SwiftUI and UIKit draw on a later run-loop turn and report no event to await.
                    try? await Task.sleep(for: .milliseconds(50))
                    host.view.layoutIfNeeded()
                    idle = !context.store.isProcessing && widths.values.count == 3 ? idle + 1 : 0
                }
                do { try await body(Hosted(window: window, host: host, widths: widths)) } catch { failure = error }
                host.presentedViewController?.dismiss(animated: false)
                // Frames for UIKit to dispose the last transition before the window is released; no event marks it.
                for _ in 0..<4 { try? await Task.sleep(for: .milliseconds(50)) }
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
                retired = window
            }
            if let failure { throw failure }
        }
    }
#endif
