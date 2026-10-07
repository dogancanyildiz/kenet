import SwiftUI

/// Section rule + title + optional tabular count (Mürekkep rule 2).
struct SectionHeader: View {
    let title: String
    /// Integer count formatted with the environment locale (grouping off).
    var count: Int? = nil
    /// Preformatted counter (e.g. Today goals `"1/3"`). Wins over ``count`` when set.
    var counter: String? = nil
    /// Shows a spinner that does not shrink the hairline rule (overlay / trailing slot).
    var isLoading: Bool = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale

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
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel(
                            Text(
                                verbatim: String(
                                    localized: "Hedefler yükleniyor",
                                    bundle: PresentationLocalization.bundle(locale), locale: locale))
                        )
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
