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

/// Whether the "Grupla" menu stretches across the page.
///
/// On Mac a ``Menu`` with button style opens as wide as its label. A label stretched to the
/// page (`expands: true`) therefore opens a window-width menu. The phone row stays full width;
/// its system menu is not sized from the label.
/// Placement of the Mac "Pano seçenekleri" menu. The control sits at the trailing edge, so the
/// menu's right edge is kept on the icon (`anchorMaxX`) and it grows to the left.
enum KanbanOptionsMenuLayout {
    static let reservedLabelWidth: CGFloat = 220

    static func menuOriginX(
        menuWidth: CGFloat, anchorMaxX: CGFloat, limitX: CGFloat, minimumX: CGFloat
    ) -> CGFloat {
        let width = max(menuWidth, 1)
        let preferred = anchorMaxX - width
        return max(min(preferred, limitX - width), minimumX)
    }
}

enum KanbanMenuLayout {
    static var groupingMenuExpands: Bool {
        #if os(macOS)
            false
        #else
            true
        #endif
    }
}
