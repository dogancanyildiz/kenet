import Testing

@testable import Journal

struct KanbanCardDragHighlightTests {
    @Test func endSessionClearsHighlightAfterDragOrCancel() {
        var highlight = KanbanCardDragHighlight.dragging
        #expect(highlight.isHighlighted)
        highlight.endSession()
        #expect(!highlight.isHighlighted)
        #expect(highlight == .idle)
    }

    @Test func idleHasNoHighlight() {
        #expect(!KanbanCardDragHighlight.idle.isHighlighted)
    }
}
