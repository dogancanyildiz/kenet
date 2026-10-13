import SwiftUI
import Testing

@testable import Journal

@Suite struct TasksListRowTouchTests {
    /// The split shell's list column selects on a touch, as on Mac: the row keeps no tap of its
    /// own there; the box and the links (subviews) keep theirs.
    @Test func splitRowLeavesTheTouchToTheListSelection() {
        #expect(TasksListRowTouch.gestureMask(in: .split) == .subviews)
        #expect(TasksListRowTouch.gestureMask(in: .tabs) == .all)
    }

    @Test func rowTapCompletesOnlyAnEnabledTaskWithoutLinks() {
        #expect(TasksListRowTouch.completes(canToggle: true, hasLinks: false))
        #expect(!TasksListRowTouch.completes(canToggle: false, hasLinks: false))
        #expect(!TasksListRowTouch.completes(canToggle: true, hasLinks: true))
    }
}
