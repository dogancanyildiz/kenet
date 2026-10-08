import CoreGraphics
import SwiftUI

/// How wide a Mac kanban column is. Columns share the board; below ``minimumColumnWidth``
/// the board scrolls instead of squeezing a card. iPhone keeps its own width in ``KanbanView``.
enum KanbanBoardLayout {
    static let columnSpacing: CGFloat = 16
    static let boardPadding: CGFloat = 12
    /// Same floor the phone column uses before it scrolls.
    static let minimumColumnWidth: CGFloat = 240

    /// Width of one column inside a board of `boardWidth` points holding `columns` columns.
    /// Horizontal padding and the gaps between columns are reserved first.
    static func columnWidth(fitting boardWidth: CGFloat, columns: Int) -> CGFloat {
        let count = max(columns, 1)
        let gaps = columnSpacing * CGFloat(count - 1)
        let available = boardWidth - boardPadding * 2 - gaps
        guard available.isFinite, available > 0 else { return minimumColumnWidth }
        return max(minimumColumnWidth, available / CGFloat(count))
    }
}

/// Laid-out width of each Mac column. A host reads this to confirm the board uses
/// ``KanbanBoardLayout/columnWidth(fitting:columns:)`` rather than a fixed width.
struct KanbanColumnWidthPreference: PreferenceKey {
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())
    }
}

/// Whether the "Grupla" menu stretches across the page.
///
/// On Mac a ``Menu`` with button style opens as wide as its label. A label stretched to the
/// page (`expands: true`) therefore opens a window-width menu. The phone row stays full width;
/// its system menu is not sized from the label.
enum KanbanMenuLayout {
    static var groupingMenuExpands: Bool {
        #if os(macOS)
            false
        #else
            true
        #endif
    }
}
