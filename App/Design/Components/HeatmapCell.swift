import SwiftUI

/// Heatmap day cell. Color alone never carries state — shape does too.
struct HeatmapCell: View {
    var kind: HeatmapCellKind
    var size: CGFloat
    /// Draws the accent “today” ring on top of any density kind (empty / partial / full).
    var isToday: Bool = false
    /// VoiceOver value supplied by the caller (e.g. "partial", "full").
    var accessibilityValue: Text
    var accessibilityLabel: Text? = nil

    var body: some View {
        Group {
            if kind.isDrawn {
                ZStack(alignment: .bottom) {
                    if kind.showsWell {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.ink.well)
                    }
                    if kind.fillHeightFraction > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fillColor)
                            .frame(height: size * kind.fillHeightFraction)
                    }
                }
                .frame(width: size, height: size)
                .overlay(alignment: .top) {
                    if kind.showsGraceDot {
                        let side = HeatmapCellKind.graceDotSide(size: size)
                        Circle()
                            .fill(Color.ink.accent)
                            .frame(width: side, height: side)
                            .offset(y: size * CGFloat(kind.graceDotCenterFraction) - side / 2)
                    }
                }
                .overlay {
                    if showsOutline {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(outlineColor, style: outlineStyle)
                    }
                }
            } else {
                Color.clear.frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? Text(verbatim: ""))
        .accessibilityValue(accessibilityValue)
        .accessibilityHidden(accessibilityLabel == nil && kind == .future)
    }

    private var fillColor: Color {
        switch kind {
        case .partial, .full, .today, .forgivenPartial, .graceSpentPartial: Color.ink.accent
        case .empty, .future, .forgiven, .graceSpent: Color.clear
        }
    }

    private var showsOutline: Bool {
        kind.showsOutline || isToday
    }

    private var outlineColor: Color {
        (isToday || kind == .today || kind.usesForgivenFrame) ? Color.ink.accent : Color.ink.control
    }

    /// Today keeps its solid ring. A forgiven day is dashed, so the two differ by shape as well.
    private var outlineStyle: StrokeStyle {
        if isToday || kind == .today { return StrokeStyle(lineWidth: InkStroke.highPriority) }
        guard kind.usesForgivenFrame else { return StrokeStyle(lineWidth: InkStroke.control) }
        return StrokeStyle(
            lineWidth: InkStroke.highPriority, lineCap: .butt, dash: HeatmapCellKind.forgivenDash(size: size))
    }
}
