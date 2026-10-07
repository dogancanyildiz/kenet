import Foundation

/// Pure progress math (kept off MainActor so unit tests stay nonisolated).
enum InkProgressMath {
    /// Tabular "n/total" for determinate progress.
    static func counterText(completed: Int, total: Int) -> String {
        "\(completed)/\(total)"
    }

    /// Clamped progress fraction in 0...1 from integer counts.
    static func fraction(completed: Int, total: Int) -> Double {
        let safeTotal = max(total, 1)
        let clamped = min(max(completed, 0), safeTotal)
        return Double(clamped) / Double(safeTotal)
    }

    /// Clamped progress fraction in 0...1 from a raw ratio (does not emit a counter).
    static func fraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    /// `done / target` clamped to 0...1. Over-target (e.g. 30/20) yields 1.
    static func ratio(done: Double, target: Double) -> Double {
        guard done.isFinite, target.isFinite else { return 0 }
        guard target > 0 else { return done > 0 ? 1 : 0 }
        return fraction(done / target)
    }

    /// VoiceOver value for counter-less fraction progress ("50%").
    static func percentText(_ value: Double) -> String {
        let percent = Int((fraction(value) * 100).rounded())
        return "\(percent)%"
    }
}
