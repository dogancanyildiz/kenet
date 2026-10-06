import SwiftUI

/// Section rule + title + optional tabular count (Mürekkep rule 2).
struct SectionHeader: View {
    let title: String
    var count: Int? = nil
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
                if let count {
                    Text(count, format: .number.grouping(.never))
                        .font(.ink.value)
                        .foregroundStyle(.ink.secondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySpokenLabel)
    }

    private var accessibilitySpokenLabel: Text {
        if let count {
            Text(verbatim: "\(title), \(count)")
        } else {
            Text(verbatim: title)
        }
    }
}
