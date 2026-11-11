#if os(iOS)
    import SwiftUI
    import Testing

    @testable import Journal

    /// Kanban and the timeline on the 13-inch in landscape, light. The shell's own task
    /// model takes the wall-clock day (the timeline's range and the board's done column follow
    /// it), so the boards are hosted as the shell's full-width page with a task model frozen on
    /// the snapshot day, in the split shell's environment.
    enum PadBoardCase: String, CaseIterable, Sendable {
        case kanbanLight, timelineLight, timelineDayLight

        var section: TasksModel.Section {
            switch self {
            case .kanbanLight: .kanban
            case .timelineLight, .timelineDayLight: .timeline
            }
        }

        var colorScheme: SnapshotColorScheme { .light }
    }

    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadBoardSnapshotTests {
        @Test(arguments: PadBoardCase.allCases)
        func board(_ snapshotCase: PadBoardCase) async throws {
            var board: KanbanModel?
            let isReady: @MainActor () -> Bool = {
                snapshotCase.section == .timeline || (board.map(Self.isLoaded) ?? false)
            }
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "board", canvas: .pad13Landscape,
                colorScheme: snapshotCase.colorScheme, shellKind: .split,
                isReady: isReady
            ) { scene in
                let tasks = TasksModel(store: scene.store, today: { snapshotDay })
                tasks.section = snapshotCase.section
                if snapshotCase == .timelineDayLight { tasks.viewState.timelineScale = .day }
                let model = KanbanModel.board(for: tasks)
                board = model
                return AnyView(
                    Group {
                        if snapshotCase.section == .timeline {
                            TaskTimelineView(tasks: tasks, showsFilters: true)
                        } else {
                            KanbanView(tasks: tasks, showsFilters: true, board: model)
                        }
                    }
                    .inkPage())
            }
        }

        /// The board's columns and its byline counts (``TasksModel/isListCurrent``) both answer the
        /// index as it is now.
        static func isLoaded(_ board: KanbanModel) -> Bool {
            board.rows != nil && board.tasks.isListCurrent
        }
    }
#endif
