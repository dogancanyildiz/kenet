#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Kenet

    enum PadBoardDetailCase: String, CaseIterable, Sendable {
        case landscapeSelectedPanel, portraitSelectedSheet

        var canvas: ShellCanvas {
            self == .landscapeSelectedPanel ? .pad13Landscape : .pad13Portrait
        }

        var presentsSheet: Bool { self == .portraitSelectedSheet }
    }

    /// The selected Kanban card on both 13-inch canvases, with 240 pt reserved for the sidebar.
    /// Uses the same frozen task model and split environment as `PadBoardSnapshotTests`.
    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadBoardDetailSnapshotTests {
        @Test(arguments: PadBoardDetailCase.allCases)
        func detail(_ snapshotCase: PadBoardDetailCase) async throws {
            // The byline ("14 açık · 5 devreden") and the columns come from loads of their own after the
            // index goes idle; captured before the list, the page sat one byline higher (run 43088834987).
            var board: KanbanModel?
            let isReady: @MainActor () -> Bool = { board.map(PadBoardSnapshotTests.isLoaded) ?? false }
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "detail", canvas: snapshotCase.canvas,
                presentsSheet: snapshotCase.presentsSheet, shellKind: .split,
                inspect: Self.checkDetail(snapshotCase),
                isReady: isReady
            ) { scene in
                let tasks = TasksModel(store: scene.store, today: { snapshotDay })
                let model = KanbanModel.board(for: tasks)
                board = model
                let row = try #require(try await scene.store.allTasks().first { !$0.isClosed && $0.rawStatus == " " })
                return AnyView(
                    HStack(spacing: 0) {
                        Color.ink.paper.frame(width: 240)
                        NavigationStack {
                            KanbanView(tasks: tasks, showsFilters: true, selection: row, board: model)
                        }
                    }.inkPage())
            }
        }

        private static func checkDetail(
            _ snapshotCase: PadBoardDetailCase
        ) -> @MainActor (UIHostingController<AnyView>) -> Void {
            { host in
                #expect((host.presentedViewController != nil) == snapshotCase.presentsSheet)
                if let sheet = host.presentedViewController {
                    #expect(ChromeSheetsDuoHost.hasVisibleRowOrField(in: sheet.view))
                }
            }
        }
    }
#endif
