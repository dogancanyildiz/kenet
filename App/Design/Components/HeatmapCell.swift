import SwiftUI

/// Heatmap day cell. Color alone never carries state — shape does too.
struct HeatmapCell: View {
    var kind: HeatmapCellKind
    var size: CGFloat
    /// VoiceOver value supplied by the caller (e.g. "partial", "full").
    var accessibilityValue: Text
    var accessibilityLabel: Text? = nil

    var body: some View {
        Group {
            if kind.isDrawn {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.ink.well)
                    if kind.fillHeightFraction > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fillColor)
                            .frame(height: size * kind.fillHeightFraction)
                    }
                }
                .frame(width: size, height: size)
                .overlay {
                    if kind.showsOutline {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(outlineColor, lineWidth: outlineWidth)
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
        case .partial, .full, .today: Color.ink.accent
        case .empty, .future: Color.clear
        }
    }

    private var outlineColor: Color {
        kind == .today ? Color.ink.accent : Color.ink.control
    }

    private var outlineWidth: CGFloat {
        kind == .today ? InkStroke.highPriority : InkStroke.control
    }
}
