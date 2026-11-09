import SwiftUI

/// Goal / day ring. Progress is an arc; completed rings fill and recede (rule 7).
struct GoalRing: View {
    /// 0…1 progress. Boolean goals use 0 or 1; numeric goals use the fraction.
    var progress: Double
    /// When true, treat as a boolean mark (empty / full) even if progress is between.
    var isBoolean: Bool = false
    /// Override diameter (default ``InkSize/goalRing``). Day header uses ``InkSize/dayRing``.
    var diameter: CGFloat? = nil
    /// Optional center label (day-header remaining count).
    var centerLabel: String? = nil

    @ScaledMetric(relativeTo: .body) private var defaultSide = InkSize.goalRing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var side: CGFloat { diameter ?? defaultSide }
    private var clamped: Double { GoalRingProgress.clamped(progress) }
    private var isComplete: Bool { GoalRingProgress.isComplete(clamped) }
    private var strokeWidth: CGFloat {
        diameter == nil ? InkStroke.control : max(InkStroke.control, side * 0.06)
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.ink.control, lineWidth: strokeWidth)
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
                            lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: clamped)
            }
            if let centerLabel {
                Text(verbatim: centerLabel)
                    .font(.system(size: side * 0.36, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(isComplete ? Color.ink.paper : Color.ink.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
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
