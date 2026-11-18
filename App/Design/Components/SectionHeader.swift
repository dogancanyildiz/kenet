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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Accessibility sizes: the counter goes under a title it does not fit beside.
                // Beside it the title was squeezed into a mid-word break ("Hede- / fler" at AX5).
                ViewThatFits(in: .horizontal) {
                    row(title: title.fixedSize())
                    VStack(alignment: .leading, spacing: 2) {
                        title.fixedSize(horizontal: false, vertical: true)
                        row(title: EmptyView(), fillsWidth: false)
                    }
                }
            } else {
                row(title: title)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySpokenLabel)
    }

    private var title: some View {
        titleText
            .font(.ink.sectionTitle)
            .foregroundStyle(.ink.text)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(Self.titleIdentifier)
    }

    /// The title, then the counter and marks; `fillsWidth` pushes them to the trailing edge.
    private func row(title: some View, fillsWidth: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            title
            if fillsWidth { Spacer(minLength: 0) }
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
