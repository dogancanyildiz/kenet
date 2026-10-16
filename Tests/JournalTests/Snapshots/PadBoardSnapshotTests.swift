#if os(iOS)
    import SwiftUI
    import Testing

    @testable import Journal

    /// Kanban and the timeline on the 13-inch in landscape, light and dark. The shell's own task
    /// model takes the wall-clock day (the timeline's range and the board's done column follow
    /// it), so the boards are hosted as the shell's full-width page with a task model frozen on
    /// the snapshot day, in the split shell's environment.
    enum PadBoardCase: String, CaseIterable, Sendable {
        case kanbanLight, kanbanDark, timelineLight, timelineDark

        var section: TasksModel.Section {
            switch self {
            case .kanbanLight, .kanbanDark: .kanban
            case .timelineLight, .timelineDark: .timeline
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .kanbanDark, .timelineDark: .dark
            default: .light
            }
        }
    }

    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadBoardSnapshotTests {
        @Test(arguments: PadBoardCase.allCases)
        func board(_ snapshotCase: PadBoardCase) async throws {
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "board", canvas: .pad13Landscape,
                colorScheme: snapshotCase.colorScheme, shellKind: .split
            ) { scene in
                let tasks = TasksModel(store: scene.store, today: { snapshotDay })
                tasks.section = snapshotCase.section
                return AnyView(
                    Group {
                        if snapshotCase.section == .timeline {
                            TaskTimelineView(tasks: tasks, showsFilters: true)
                        } else {
                            KanbanView(tasks: tasks, showsFilters: true)
                        }
                    }
                    .inkPage())
            }
        }
    }
#endif
