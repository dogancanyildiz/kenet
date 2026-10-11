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
                .overlay {
                    if showsOutline {
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
        case .empty, .future, .forgiven: Color.clear
        }
    }

    private var showsOutline: Bool {
        kind.showsOutline || isToday
    }

    private var outlineColor: Color {
        (isToday || kind == .today || kind.usesAccentFrame) ? Color.ink.accent : Color.ink.control
    }

    private var outlineWidth: CGFloat {
        (isToday || kind == .today || kind.usesAccentFrame) ? InkStroke.highPriority : InkStroke.control
    }
}
