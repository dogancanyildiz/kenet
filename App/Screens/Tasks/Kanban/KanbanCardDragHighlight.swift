import Foundation

/// Drag highlight for a Mac kanban card. Highlight must clear when the drag ends
/// (drop into any column, including the source, or cancel).
struct KanbanCardDragHighlight: Equatable, Sendable {
    var isHighlighted: Bool

    static var idle: Self { Self(isHighlighted: false) }
    static var dragging: Self { Self(isHighlighted: true) }

    /// Call when the system drag session ends (drop or cancel).
    mutating func endSession() {
        isHighlighted = false
    }
}
