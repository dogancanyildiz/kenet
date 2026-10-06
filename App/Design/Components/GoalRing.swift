import SwiftUI

/// 22 pt goal ring. Progress is an arc; completed rings fill and recede (rule 7).
struct GoalRing: View {
    /// 0…1 progress. Boolean goals use 0 or 1; numeric goals use the fraction.
    var progress: Double
    /// When true, treat as a boolean mark (empty / full) even if progress is between.
    var isBoolean: Bool = false

    @ScaledMetric(relativeTo: .body) private var side = InkSize.goalRing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { GoalRingProgress.clamped(progress) }
    private var isComplete: Bool { GoalRingProgress.isComplete(clamped) }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
            if isComplete {
                Circle()
                    .fill(Color.ink.secondaryText)
            } else if isBoolean {
                EmptyView()
            } else if clamped > 0 {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        Color.ink.accent,
                        style: StrokeStyle(
                            lineWidth: InkStroke.control, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: clamped)
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement()
        .accessibilityLabel(Text("Hedef"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
    }

    private var accessibilityValue: String {
        if isComplete {
            return String(localized: "Tamamlandı")
        }
        if isBoolean {
            return String(localized: "Açık")
        }
        let percent = Int((clamped * 100).rounded())
        return "\(percent)%"
    }
}

enum GoalRingProgress {
    static func clamped(_ progress: Double) -> Double {
        min(1, max(0, progress))
    }

    static func isComplete(_ progress: Double) -> Bool {
        clamped(progress) >= 1
    }
}
