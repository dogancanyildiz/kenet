import SwiftUI

/// Section rule + title + optional tabular count (Mürekkep rule 2).
struct SectionHeader: View {
    private let titleText: Text
    private let spokenTitle: String?
    /// Integer count formatted with the environment locale (grouping off).
    var count: Int? = nil
    /// Preformatted counter (e.g. Today goals `"1/3"`). Wins over ``count`` when set.
    var counter: String? = nil
    /// Shows a spinner that does not shrink the hairline rule (overlay / trailing slot).
    var isLoading: Bool = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale

    /// Already-localized or verbatim title (callers that used `String(localized:)`).
    init(title: String, count: Int? = nil, counter: String? = nil, isLoading: Bool = false) {
        self.titleText = Text(verbatim: title)
        self.spokenTitle = title
        self.count = count
        self.counter = counter
        self.isLoading = isLoading
    }

    /// Catalog key resolved with the SwiftUI environment locale (snapshot-safe).
    init(
        _ titleKey: LocalizedStringKey, count: Int? = nil, counter: String? = nil,
        isLoading: Bool = false
    ) {
        self.titleText = Text(titleKey)
        self.spokenTitle = nil
        self.count = count
        self.counter = counter
        self.isLoading = isLoading
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
                if let counterText {
                    Text(verbatim: counterText)
                        .font(.ink.value)
                        .foregroundStyle(.ink.secondaryText)
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
        if let count { return count.formatted(.number.grouping(.never).locale(locale)) }
        return nil
    }

    private var accessibilitySpokenLabel: Text {
        if let spokenTitle {
            if let counterText {
                return Text(verbatim: "\(spokenTitle), \(counterText)")
            }
            return Text(verbatim: spokenTitle)
        }
        if let counterText {
            return Text("\(titleText), \(counterText)")
        }
        return titleText
    }
}
