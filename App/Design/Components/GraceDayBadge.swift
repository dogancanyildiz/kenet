import SwiftUI

/// Chain-day balance after a goal's name: a link glyph and the count in a thin capsule. It is a
/// note, not an action, so it stays in secondary text with a control-line outline; the glyph and
/// the number carry it without color. VoiceOver reads `label` ("2 zincir günü").
struct GraceDayBadge: View {
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "link")
                .imageScale(.small)
            Text(verbatim: count.formatted())
                .monospacedDigit()
        }
        .font(.ink.meta)
        .foregroundStyle(Color.ink.secondaryText)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .overlay {
            Capsule(style: .circular).strokeBorder(Color.ink.control, lineWidth: InkStroke.rule)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }
}
