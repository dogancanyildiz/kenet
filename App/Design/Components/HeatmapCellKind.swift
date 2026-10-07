import Foundation

/// Heatmap day cell kind. Color alone never carries state — shape does too.
enum HeatmapCellKind: String, CaseIterable, Sendable {
    case empty
    case partial
    case full
    case today
    case future

    /// Fill height as a fraction of the cell (shape cue for density).
    var fillHeightFraction: Double {
        switch self {
        case .empty, .future: 0
        case .partial: 0.45
        case .full, .today: 1
        }
    }

    /// Whether the well outline is drawn (empty / today ring).
    var showsOutline: Bool {
        switch self {
        case .empty, .today: true
        case .partial, .full, .future: false
        }
    }

    /// Whether the cell is intentionally blank (future days).
    var isDrawn: Bool {
        self != .future
    }
}
