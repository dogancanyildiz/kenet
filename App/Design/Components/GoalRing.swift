import SwiftUI

/// Goal / day ring. Progress is an arc; a completed ring is a full accent ring (user decision
/// 2026-11-09: rings are mürdüm, no done green and no receding gray). Any diameter: pass ``diameter`` for the large summary ring.
struct GoalRing: View {
    /// 0…1 progress. Boolean goals use 0 or 1; numeric goals use the fraction.
    var progress: Double
    /// When true, treat as a boolean mark (empty / full) even if progress is between.
    var isBoolean: Bool = false
    /// Override diameter (default ``InkSize/goalRing``). Day header uses ``InkSize/dayRing``.
    var diameter: CGFloat? = nil
    /// Optional center label (day-header remaining count).
    var centerLabel: String? = nil
    /// Thicker accent arc on a light track (day ring, goal detail): the drawing's progress ring.
    var emphasizesArc: Bool = false

    @ScaledMetric(relativeTo: .body) private var defaultSide = InkSize.goalRing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var side: CGFloat { diameter ?? defaultSide }
    private var clamped: Double { GoalRingProgress.clamped(progress) }
    private var isComplete: Bool { GoalRingProgress.isComplete(clamped) }
    private var strokeWidth: CGFloat {
        if emphasizesArc { return max(InkStroke.control, side * 0.1) }
        return diameter == nil ? InkStroke.control : max(InkStroke.control, side * 0.06)
    }

    /// The track under the arc: light on an emphasized ring, so the accent arc carries the
    /// value; the control color elsewhere.
    private var trackColor: Color { emphasizesArc ? Color.ink.rule : Color.ink.control }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(trackColor, lineWidth: strokeWidth)
            if isComplete {
                // A full accent ring, not a filled disc (drawing; rings are mürdüm, no done green).
                Circle()
                    .strokeBorder(GoalRingProgress.completeColor, lineWidth: strokeWidth)
            } else if isBoolean {
                EmptyView()
            } else if clamped > 0 {
                Circle()
                    .inset(by: strokeWidth / 2)
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
                    .font(.system(size: side * (emphasizesArc ? 0.3 : 0.36), weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink.text)
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
    /// Color of a completed ring: the accent, like the progress arc (fark2 O1).
    static var completeColor: Color { Color.ink.accent }

    static func clamped(_ progress: Double) -> Double {
        min(1, max(0, progress))
    }

    static func isComplete(_ progress: Double) -> Bool {
        clamped(progress) >= 1
    }
}
