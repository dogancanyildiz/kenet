#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

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
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "detail", canvas: snapshotCase.canvas,
                presentsSheet: snapshotCase.presentsSheet, shellKind: .split,
                inspect: Self.checkDetail(snapshotCase)
            ) { scene in
                let tasks = TasksModel(store: scene.store, today: { snapshotDay })
                let row = try #require(try await scene.store.allTasks().first { !$0.isClosed && $0.rawStatus == " " })
                return AnyView(
                    HStack(spacing: 0) {
                        Color.ink.paper.frame(width: 240)
                        NavigationStack {
                            KanbanView(tasks: tasks, showsFilters: true, selection: row)
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
