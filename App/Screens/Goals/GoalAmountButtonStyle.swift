import SwiftUI

/// The goal page's "Miktar gir" pill: the drawing's grey filled capsule with a hairline frame and a
/// subheadline semibold label, smaller than ``InkSecondaryButtonStyle``'s byline text.
struct GoalAmountButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.ink.text : Color.ink.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: TapTarget.minimumLength)
            .background {
                Capsule()
                    .fill(Color.ink.well)
                    .overlay(Capsule().strokeBorder(Color.ink.line, lineWidth: 1))
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
