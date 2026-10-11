import Foundation

/// Heatmap day cell kind. Color alone never carries state — shape does too.
enum HeatmapCellKind: String, CaseIterable, Sendable {
    case empty
    case partial
    case full
    case today
    case future
    /// Isolated miss on a daily goal with no contribution: hollow cell in a dashed accent frame.
    case forgiven
    /// Forgiven day that stayed below the target: the partial fill stays, inside the same dashed frame.
    case forgivenPartial

    /// Fill height as a fraction of the cell (shape cue for density).
    var fillHeightFraction: Double {
        switch self {
        case .empty, .future, .forgiven: 0
        case .partial, .forgivenPartial: 0.45
        case .full, .today: 1
        }
    }

    /// Whether the well outline is drawn (empty / today ring / forgiven frame).
    var showsOutline: Bool {
        switch self {
        case .empty, .today, .forgiven, .forgivenPartial: true
        case .partial, .full, .future: false
        }
    }

    /// Empty and density cells sit in the well. A forgiven day with no contribution is hollow.
    var showsWell: Bool {
        switch self {
        case .future, .forgiven: false
        case .empty, .partial, .full, .today, .forgivenPartial: true
        }
    }

    /// Dashed accent frame. The dashes, not the color, tell it from the solid ring around today.
    var usesForgivenFrame: Bool {
        self == .forgiven || self == .forgivenPartial
    }

    /// Dash and gap of the forgiven frame: three dashes a side at any cell size.
    static func forgivenDash(size: CGFloat) -> [CGFloat] {
        let unit = max(size, 1) / 6
        return [unit, unit]
    }

    /// Whether the cell is intentionally blank (future days).
    var isDrawn: Bool {
        self != .future
    }
}
