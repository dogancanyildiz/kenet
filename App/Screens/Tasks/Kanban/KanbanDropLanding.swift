import Foundation

/// Where a dragged card lands on the touch board: the column the finger is over and the place
/// the card takes there. A column sorts its own cards (``KanbanModel/order(_:_:)``: due date,
/// priority, text), so a drop cannot pick a position; the board marks the place the order
/// gives instead.
struct KanbanDropLanding: Equatable, Sendable {
    /// ``KanbanColumn/id`` of the column the card moves to.
    let columnID: String
    /// Index among that column's cards after the move.
    let index: Int

    /// `nil` when the board would not move the card there (its own column, the person
    /// grouping, a busy or read-only vault: ``KanbanModel/canMove(_:to:)``).
    @MainActor static func resolve(_ row: TaskRow, over column: KanbanColumn, in model: KanbanModel) -> Self? {
        guard model.canMove(row, to: column) else { return nil }
        return Self(columnID: column.id, index: index(of: row, among: column.rows))
    }

    /// The card a touch drag carries, looked up once for the whole board while the drag lasts
    /// (not by every column's body). Mac marks the column alone: `nil`.
    @MainActor static func draggedRow(in model: KanbanModel, columns: [KanbanColumn]) -> TaskRow? {
        #if os(iOS)
            guard let id = model.draggingRowID else { return nil }
            return columns.lazy.flatMap(\.rows).first { $0.id == id }
        #else
            nil
        #endif
    }

    /// The card's place among `rows` (already in board order) once it joins them. The move
    /// changes the status or the project, never the keys the order reads.
    nonisolated static func index(of row: TaskRow, among rows: [TaskRow]) -> Int {
        let others = rows.filter { $0.id != row.id }
        return others.firstIndex { KanbanModel.order(row, $0) } ?? others.count
    }
}
