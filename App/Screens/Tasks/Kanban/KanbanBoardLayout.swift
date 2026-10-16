import CoreGraphics
import SwiftUI

/// How wide a desktop kanban column is. Columns share the board; below ``minimumColumnWidth``
/// the board scrolls instead of squeezing a card. The phone board keeps its own width
/// (``phoneColumnWidth(fitting:)``).
enum KanbanBoardLayout {
    static let columnSpacing: CGFloat = 16
    static let boardPadding: CGFloat = 12
    /// Same floor the phone column uses before it scrolls.
    static let minimumColumnWidth: CGFloat = 240
    /// The phone column never grows past this; a wider screen pages one column at a time.
    static let maximumPhoneColumnWidth: CGFloat = 360

    /// Width of one column inside a board of `boardWidth` points holding `columns` columns.
    /// Horizontal padding and the gaps between columns are reserved first.
    static func columnWidth(fitting boardWidth: CGFloat, columns: Int) -> CGFloat {
        let count = max(columns, 1)
        let gaps = columnSpacing * CGFloat(count - 1)
        let available = boardWidth - boardPadding * 2 - gaps
        guard available.isFinite, available > 0 else { return minimumColumnWidth }
        return max(minimumColumnWidth, available / CGFloat(count))
    }

    /// The phone column: the board's width less a peek of the next column, between the floor and
    /// ``maximumPhoneColumnWidth``.
    static func phoneColumnWidth(fitting boardWidth: CGFloat) -> CGFloat {
        let width = boardWidth.isFinite ? max(0, boardWidth - 32) : 0
        return max(minimumColumnWidth, min(maximumPhoneColumnWidth, width))
    }
}

/// Which board the shell draws (unit-tested). The desktop board is the Mac window's and the
/// split iOS shell's (iPad, iPhone Duo inner screen): columns share the width, the board
/// scrolls freely, the detail sits beside it while it fits (``KanbanDetailPlacement``), the
/// "Grupla" menu hugs its label and a card is dragged between columns. The phone board is the
/// tab shell's: one column per page, the detail in a sheet, the full-width menu row and no
/// drag ("Taşı" in the card's menu moves it).
enum KanbanBoardStyle: Equatable, Sendable {
    case desktop
    case phone

    static func resolve(shell: ShellKind) -> Self {
        #if os(macOS)
            .desktop
        #else
            shell == .split ? .desktop : .phone
        #endif
    }

    func columnWidth(fitting boardWidth: CGFloat, columns: Int) -> CGFloat {
        switch self {
        case .desktop: KanbanBoardLayout.columnWidth(fitting: boardWidth, columns: columns)
        case .phone: KanbanBoardLayout.phoneColumnWidth(fitting: boardWidth)
        }
    }

    /// The phone board snaps to whole columns; the desktop board scrolls freely.
    var pagesColumns: Bool { self == .phone }

    /// Whether the "Grupla" menu stretches across the page.
    ///
    /// On Mac a ``Menu`` with button style opens as wide as its label. A label stretched to the
    /// page (`expands: true`) therefore opens a window-width menu. The phone row stays full
    /// width; its system menu is not sized from the label.
    var groupingMenuExpands: Bool { self == .phone }

    /// A card can be dragged to another column. On touch the drag starts with a long press, so
    /// a swipe across the board still scrolls it.
    var dragsCards: Bool { self == .desktop }
}

/// Laid-out width of each kanban column. A host reads this to confirm the board uses
/// ``KanbanBoardStyle/columnWidth(fitting:columns:)`` rather than a fixed width.
struct KanbanColumnWidthPreference: PreferenceKey {
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())
    }
}
