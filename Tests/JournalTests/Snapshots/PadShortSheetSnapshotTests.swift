#if os(iOS)
    import SwiftUI
    import Testing

    @testable import Journal

    enum PadShortSheetCase: String, CaseIterable, Sendable {
        case taskDateLight, taskRecurrenceLight, taskTextLight, goalAmountLight

        @MainActor func editor(store: IndexStore) async throws -> AnyView {
            if self == .goalAmountLight {
                let day = GoalDayModel(store: store, day: goalsSnapshotDay)
                await day.load()
                let goal = try #require(day.goals.first { $0.key == "kitap" })
                return AnyView(
                    NavigationStack { GoalValueEditor(model: GoalValueModel(dayModel: day, goal: goal)) }
                        .inkAdaptiveSheetPresentation(fitsContent: true, usesPhoneDetents: false))
            }
            let rows = try await store.allTasks()
            let row = try #require(rows.first { !$0.isClosed && $0.due == snapshotDay })
            let model = TaskEditorModel(store: store, row: row)
            await model.load()
            switch self {
            case .taskDateLight:
                return AnyView(
                    NavigationStack { TaskDateEditor(model: model) }
                        .frame(minWidth: 320, minHeight: 200)
                        .inkAdaptiveSheetPresentation(fitsContent: true))
            case .taskRecurrenceLight:
                return AnyView(
                    NavigationStack { TaskRecurrenceEditor(model: model) }
                        .inkAdaptiveSheetPresentation(fitsContent: true))
            case .taskTextLight:
                return AnyView(
                    NavigationStack { TaskTextEditor(model: model) }
                        .frame(minWidth: 320, minHeight: 200)
                        .inkAdaptiveSheetPresentation(fitsContent: true))
            case .goalAmountLight:
                preconditionFailure("Handled above")
            }
        }
    }

    /// Same NavigationStack and presentation modifiers as the row and goal presenters.
    struct PadShortSheetContent: View {
        let editor: AnyView
        var background = AnyView(Color.ink.paper)
        @State private var presentsSheet = false

        var body: some View {
            background
                .onAppear { presentsSheet = true }
                .sheet(isPresented: $presentsSheet) { editor }
        }
    }

    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadShortSheetSnapshotTests {
        @Test(arguments: [
            PadShortSheetCase.taskDateLight, .taskRecurrenceLight, .goalAmountLight,
        ])
        func sheet(_ sheet: PadShortSheetCase) async throws {
            try await PadSnapshotHost.assertWindow(
                named: sheet.rawValue, testName: "sheet", canvas: .pad13Portrait,
                presentsSheet: true, shellKind: .split, masks: [PadSnapshotHost.Mask.sidebarButton]
            ) { scene in
                AnyView(
                    PadShortSheetContent(
                        editor: try await sheet.editor(store: scene.store),
                        background: AnyView(AdaptiveNavigation(store: scene.store))))
            }
        }
    }
#endif
