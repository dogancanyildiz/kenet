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

    @MainActor
    @Test func beginDragHighlightsRowAndAbandonClears() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = KanbanModel(tasks: TasksModel(store: context.store))
        let row = try #require(context.store.content.tasks.first)
        #expect(model.dragHighlight == .idle)
        let token = model.beginDrag(row)
        #expect(model.dragHighlight == .dragging)
        #expect(model.draggingRowID == row.id)
        model.abandonDrag(token)
        #expect(model.dragHighlight == .idle)
        #expect(model.draggingRowID == nil)
    }
}
