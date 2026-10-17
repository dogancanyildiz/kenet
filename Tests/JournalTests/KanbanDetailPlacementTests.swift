import SwiftUI
import Testing

@testable import Journal

@Suite struct KanbanDetailPlacementTests {
    /// The panel reserves two complete columns, their gap and both board margins.
    @Test(arguments: [
        (width: 0, panel: false),
        (width: 626, panel: false),
        (width: 792, panel: false),
        (width: 859, panel: false),
        (width: 860, panel: true),
        (width: 890, panel: true),
        (width: 1032, panel: true),
        (width: 1136, panel: true),
    ])
    func splitShellRequiresTwoCompleteColumns(width: Int, panel: Bool) {
        #expect(KanbanDetailPlacement.usesPanel(shell: .split, width: CGFloat(width)) == panel)
    }

    @Test(arguments: [0, 792, 859, 860, 890, 1032, 1136, 2000])
    func tabShellAlwaysPresentsTheSheet(width: Int) {
        #expect(!KanbanDetailPlacement.usesPanel(shell: .tabs, width: CGFloat(width)))
    }
}
