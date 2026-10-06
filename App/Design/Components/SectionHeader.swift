import SwiftUI

/// Section rule + title + optional tabular count (Mürekkep rule 2).
struct SectionHeader: View {
    let title: String
    /// Integer count formatted with the environment locale (grouping off).
    var count: Int? = nil
    /// Preformatted counter (e.g. Today goals `"1/3"`). Wins over ``count`` when set.
    var counter: String? = nil
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.ink.rule)
                .frame(height: InkStroke.hairline(scale: displayScale))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: title)
                    .font(.ink.section)
                    .foregroundStyle(.ink.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let counterText {
                    Text(verbatim: counterText)
                        .font(.ink.value)
                        .foregroundStyle(.ink.secondaryText)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySpokenLabel)
    }

    private var counterText: String? {
        if let counter, !counter.isEmpty { return counter }
        if let count { return count.formatted(.number.grouping(.never)) }
        return nil
    }

    private var accessibilitySpokenLabel: Text {
        if let counterText {
            Text(verbatim: "\(title), \(counterText)")
        } else {
            Text(verbatim: title)
        }
    }
}
