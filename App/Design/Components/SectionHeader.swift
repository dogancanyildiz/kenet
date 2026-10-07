import SwiftUI

/// Section rule + title + optional tabular count (Mürekkep rule 2).
struct SectionHeader: View {
    private let titleText: Text
    private let spokenTitle: String?
    var count: Int? = nil
    @Environment(\.displayScale) private var displayScale

    /// Already-localized or verbatim title (callers that used `String(localized:)`).
    init(title: String, count: Int? = nil) {
        self.titleText = Text(verbatim: title)
        self.spokenTitle = title
        self.count = count
    }

    /// Catalog key resolved with the SwiftUI environment locale (snapshot-safe).
    init(_ titleKey: LocalizedStringKey, count: Int? = nil) {
        self.titleText = Text(titleKey)
        self.spokenTitle = nil
        self.count = count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.ink.rule)
                .frame(height: InkStroke.hairline(scale: displayScale))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
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
        if let spokenTitle {
            if let count {
                return Text(verbatim: "\(spokenTitle), \(count)")
            }
            return Text(verbatim: spokenTitle)
        }
        if let count {
            return Text("\(titleText), \(count)")
        }
        return titleText
    }
}
