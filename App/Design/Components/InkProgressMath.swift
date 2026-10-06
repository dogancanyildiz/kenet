import Foundation

/// Pure progress math (kept off MainActor so unit tests stay nonisolated).
enum InkProgressMath {
    /// Tabular "n/total" for determinate progress.
    static func counterText(completed: Int, total: Int) -> String {
        "\(completed)/\(total)"
    }

    /// Clamped progress fraction in 0...1.
    static func fraction(completed: Int, total: Int) -> Double {
        let safeTotal = max(total, 1)
        let clamped = min(max(completed, 0), safeTotal)
        return Double(clamped) / Double(safeTotal)
    }
}
