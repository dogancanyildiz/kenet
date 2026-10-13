import Testing

@testable import Journal

@Suite struct KanbanDetailPlacementTests {
    /// The iPhone Duo inner screen (890 pt) keeps the board beside the 340 pt panel; the
    /// upright inner screen (626 pt) still fits a column at its floor; narrower goes to a sheet.
    @Test func splitShellKeepsThePanelWhileAColumnFitsBesideIt() {
        let threshold = KanbanDetailPlacement.panelWidth + KanbanDetailPlacement.minimumBoardWidth
        #expect(threshold == 612)
        #expect(KanbanDetailPlacement.usesPanel(shell: .split, width: 890))
        #expect(KanbanDetailPlacement.usesPanel(shell: .split, width: 626))
        #expect(KanbanDetailPlacement.usesPanel(shell: .split, width: threshold))
        #expect(!KanbanDetailPlacement.usesPanel(shell: .split, width: threshold - 1))
        #expect(!KanbanDetailPlacement.usesPanel(shell: .split, width: 0))
    }

    @Test func tabShellAlwaysPresentsTheSheet() {
        #expect(!KanbanDetailPlacement.usesPanel(shell: .tabs, width: 890))
        #expect(!KanbanDetailPlacement.usesPanel(shell: .tabs, width: 2000))
    }
}
