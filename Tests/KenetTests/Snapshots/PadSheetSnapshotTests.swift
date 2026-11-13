#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Kenet

    /// Sheets over the iPad shell on the 13-inch in landscape, light: Ayarlar (the Today
    /// manşet's gear, through the real `AdaptiveNavigation`), Ara (the system sheet `ContentView`
    /// presents above the shell), Günü kapat (the evening reminder's route on Today) and the
    /// task detail a board narrower than its panel threshold presents.
    enum PadSheetCase: String, CaseIterable, Sendable {
        case settingsLight
        case searchLight
        case closeDayLight
        case taskDetailLight

        enum Sheet: Sendable { case settings, search, closeDay, taskDetail }

        var sheet: Sheet {
            switch self {
            case .settingsLight: .settings
            case .searchLight: .search
            case .closeDayLight: .closeDay
            case .taskDetailLight: .taskDetail
            }
        }

        /// Search is hosted but not drawn: its field takes focus and the simulator keyboard moves
        /// the system sheet, so two runs differ (as in `ChromeSheetsDuoSnapshotTests`). The
        /// hosted case still checks that the sheet is up with its field on screen.
        var isDrawn: Bool { sheet != .search }

        var dynamicType: SnapshotDynamicType { .medium }
    }

    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadSheetSnapshotTests {
        @Test(arguments: PadSheetCase.allCases)
        func sheet(_ snapshotCase: PadSheetCase) async throws {
            // The task detail sits over a board, not a day page: its columns and byline come from
            // loads of their own after the index goes idle. Captured before them, the page behind
            // the sheet was empty (run 43456271642).
            var board: KanbanModel?
            let isReady: @MainActor () -> Bool = {
                snapshotCase.sheet != .taskDetail || board.map(PadBoardSnapshotTests.isLoaded) ?? false
            }
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "sheet", canvas: .pad13Landscape,
                dynamicType: snapshotCase.dynamicType, presentsSheet: true,
                shellKind: snapshotCase.sheet == .taskDetail ? .split : nil,
                masks: snapshotCase.sheet == .taskDetail ? [] : [PadSnapshotHost.Mask.sidebarButton],
                inspect: Self.checkSheet(snapshotCase),
                isReady: isReady,
                draws: snapshotCase.isDrawn
            ) { scene in
                let store = scene.store
                switch snapshotCase.sheet {
                case .settings:
                    return AnyView(AdaptiveNavigation(store: store, showsSettings: true))
                case .search:
                    return AnyView(PadSearchSheetContent(store: store))
                case .closeDay:
                    // The evening reminder's route: Today opens its close-day sheet on the diary step.
                    scene.notifications.open(.diary)
                    return AnyView(AdaptiveNavigation(store: store))
                case .taskDetail:
                    let tasks = TasksModel(store: store, today: { snapshotDay })
                    tasks.section = .kanban
                    let model = KanbanModel.board(for: tasks)
                    board = model
                    let row = try #require(try await store.allTasks().first { !$0.isClosed })
                    // Narrower than the panel threshold: the board presents its own sheet.
                    return AnyView(
                        NavigationStack { KanbanView(tasks: tasks, showsFilters: true, selection: row, board: model) }
                            .frame(width: 600)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .inkPage())
                }
            }
        }
    }

    extension PadSheetSnapshotTests {
        /// The presented sheet is tall enough and shows a row or an input.
        static func checkSheet(_ snapshotCase: PadSheetCase) -> @MainActor (UIHostingController<AnyView>) -> Void {
            { host in
                let sheet = host.presentedViewController
                #expect((sheet?.view.bounds.height ?? 0) >= 360, "\(snapshotCase): sheet too short")
                #expect(
                    sheet.map { ChromeSheetsDuoHost.hasVisibleRowOrField(in: $0.view) } ?? false,
                    "\(snapshotCase): the sheet must contain a visible row or input.")
            }
        }
    }

    /// Search is the one sheet presented above the shell (`ContentView`), as in production.
    private struct PadSearchSheetContent: View {
        let store: IndexStore
        @State private var presentsSearch = false

        var body: some View {
            AdaptiveNavigation(store: store)
                .onAppear { presentsSearch = true }
                .sheet(isPresented: $presentsSearch) { SearchView(store: store) }
        }
    }
#endif
