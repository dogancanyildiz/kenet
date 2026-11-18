import SwiftUI

/// Section title + optional tabular count above a card (Şafak rule 2). No decorative rule.
struct SectionHeader: View {
    /// Identifiers of the title and the counter text. They name the component, not one section: the
    /// UI accessibility audit treats every section title alike (`AccessibilityAuditExemption`).
    /// The spoken label and the drawing do not change; a caller's identifier still names the header.
    static let titleIdentifier = "sectionHeader"
    static let counterIdentifier = "sectionHeader.count"

    private let titleText: Text
    private let spokenTitle: String?
    /// Integer count formatted with the environment locale (grouping off).
    var count: Int? = nil
    /// Preformatted counter (e.g. Today goals `"1/3"`). Wins over ``count`` when set.
    var counter: String? = nil
    /// Shows a spinner that does not shrink the title row.
    var isLoading: Bool = false
    /// Shows a disclosure chevron (pointing down when expanded, right when collapsed) aligned with the title.
    var isExpanded: Bool? = nil
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Already-localized or verbatim title (callers that used `String(localized:)`).
    init(
        title: String, count: Int? = nil, counter: String? = nil, isLoading: Bool = false,
        isExpanded: Bool? = nil
    ) {
        self.titleText = Text(verbatim: title)
        self.spokenTitle = title
        self.count = count
        self.counter = counter
        self.isLoading = isLoading
        self.isExpanded = isExpanded
    }

    /// Catalog key resolved with the SwiftUI environment locale (snapshot-safe).
    init(
        _ titleKey: LocalizedStringKey, count: Int? = nil, counter: String? = nil,
        isLoading: Bool = false, isExpanded: Bool? = nil
    ) {
        self.titleText = Text(titleKey)
        self.spokenTitle = nil
        self.count = count
        self.counter = counter
        self.isLoading = isLoading
        self.isExpanded = isExpanded
    }

    var body: some View {
        // Accessibility sizes: the counter and marks go on a line of their own under the title. Beside
        // it the title was squeezed into a mid-word break ("Hede- / fler" at AX5). One layout keeps the
        // title the same view at every size: the accessibility audit measures it while it grows, and a
        // title that changes views as it grows (if/else, ViewThatFits) reads to it as clipped (iPad
        // Tasks, "Carried over").
        let stacks = dynamicTypeSize.isAccessibilitySize
        let layout =
            stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            titleText
                .font(.ink.sectionTitle)
                .foregroundStyle(.ink.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.titleIdentifier)
            if stacks {
                HStack(alignment: .firstTextBaseline, spacing: 8) { marks }
            } else {
                Spacer(minLength: 0)
                marks
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySpokenLabel)
    }

    /// The counter, the disclosure chevron and the loading mark, in this order after the title.
    @ViewBuilder private var marks: some View {
        if let counterText {
            Text(verbatim: counterText)
                // Drawing: a footnote counter beside the section title ("6 kaldı", "4 görev").
                .font(.ink.meta.monospacedDigit())
                .foregroundStyle(.ink.secondaryText)
                // Whole at every text size, never cut (audit "Text clipped" on "1 day"); the
                // title beside it wraps instead.
                .fixedSize()
                .layoutPriority(1)
                .accessibilityHidden(true)
                .accessibilityIdentifier(Self.counterIdentifier)
        }
        if let isExpanded {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
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
