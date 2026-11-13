import SwiftUI

/// The visible text field of a form sheet (drawing: Yeni hedef): a filled box, an accent
/// outline while editing. The caller passes its own focus state.
struct InkFieldBox: ViewModifier {
    let isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                    .fill(isFocused ? Color.ink.surface : Color.ink.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                    .stroke(
                        isFocused ? Color.ink.accent : Color.ink.rule,
                        lineWidth: isFocused ? 1.5 : InkStroke.hairline(scale: displayScale))
            )
    }
}
