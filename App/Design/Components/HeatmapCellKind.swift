import Foundation

/// Heatmap day cell kind. Color alone never carries state — shape does too.
enum HeatmapCellKind: String, CaseIterable, Sendable {
    case empty
    case partial
    case full
    case today
    case future
    /// Isolated miss on a daily goal: hollow accent frame, not a density fill.
    case forgiven

    /// Fill height as a fraction of the cell (shape cue for density).
    var fillHeightFraction: Double {
        switch self {
        case .empty, .future, .forgiven: 0
        case .partial: 0.45
        case .full, .today: 1
        }
    }

    /// Whether the well outline is drawn (empty / today ring / forgiven frame).
    var showsOutline: Bool {
        switch self {
        case .empty, .today, .forgiven: true
        case .partial, .full, .future: false
        }
    }

    /// Empty and density cells sit in the well. Forgiven is hollow so the frame is the cue.
    var showsWell: Bool {
        switch self {
        case .future, .forgiven: false
        case .empty, .partial, .full, .today: true
        }
    }

    /// Accent frame, distinct from the empty cell's control stroke.
    var usesAccentFrame: Bool {
        self == .forgiven
    }

    /// Whether the cell is intentionally blank (future days).
    var isDrawn: Bool {
        self != .future
    }
}
