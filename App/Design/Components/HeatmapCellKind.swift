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
    /// Miss covered by a spent chain day: the forgiven frame with an accent dot in the empty part.
    case graceSpent
    /// Chain-day miss that stayed below the target: the partial fill, the frame and the dot above it.
    case graceSpentPartial

    /// Fill height as a fraction of the cell (shape cue for density).
    var fillHeightFraction: Double {
        switch self {
        case .empty, .future, .forgiven, .graceSpent: 0
        case .partial, .forgivenPartial, .graceSpentPartial: 0.45
        case .full, .today: 1
        }
    }

    /// Whether the well outline is drawn (empty / today ring / forgiven frame).
    var showsOutline: Bool {
        switch self {
        case .empty, .today, .forgiven, .forgivenPartial, .graceSpent, .graceSpentPartial: true
        case .partial, .full, .future: false
        }
    }

    /// Empty and density cells sit in the well. A forgiven or chain-day miss with no contribution is hollow.
    var showsWell: Bool {
        switch self {
        case .future, .forgiven, .graceSpent: false
        case .empty, .partial, .full, .today, .forgivenPartial, .graceSpentPartial: true
        }
    }

    /// Dashed accent frame. The dashes, not the color, tell it from the solid ring around today.
    /// A chain-day miss shares it: both are misses that kept the chain.
    var usesForgivenFrame: Bool {
        switch self {
        case .forgiven, .forgivenPartial, .graceSpent, .graceSpentPartial: true
        case .empty, .partial, .full, .today, .future: false
        }
    }

    /// Accent dot of a spent chain day: the shape, not the color, tells it from a forgiven day.
    var showsGraceDot: Bool {
        self == .graceSpent || self == .graceSpentPartial
    }

    /// Dot side as a fraction of the cell; never under 3 pt so the legend cell keeps it.
    static func graceDotSide(size: CGFloat) -> CGFloat {
        max(3, (size * 0.3).rounded())
    }

    /// Dot center from the cell's top, as a fraction of the cell: the middle of the part the fill
    /// leaves empty, so the dot never sits on the partial fill.
    var graceDotCenterFraction: Double {
        (1 - fillHeightFraction) / 2
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
