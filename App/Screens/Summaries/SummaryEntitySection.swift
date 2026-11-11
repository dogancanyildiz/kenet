import Summaries
import SwiftUI

/// The top five people or places inside an `InkCard`, with circle (`person`) or diamond (`place`)
/// badges; each row opens its page. A sparkle marks a name first mentioned in the period.
struct SummaryEntitySection: View {
    let store: IndexStore
    let title: String
    let entities: [SummaryEntityCount]
    let mentions: Int
    let firsts: [SummaryFirstMention]
    let kind: SummaryInput.Entity.Kind
    @Environment(\.locale) private var locale

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    private var bundle: Bundle { PresentationLocalization.bundle(locale) }

    /// Title and mention count above the card; rows with dividers inside it (Şafak çizimi).
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, count: mentions)
            InkCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entities.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { InkCardDivider() }
                        row(item)
                    }
                }
            }
            if !firsts.isEmpty {
                Label {
                    Text(verbatim: SummaryPresentation.firstNames(firsts, kind: kind, locale: locale))
                } icon: {
                    Image(systemName: "sparkle")
                        .accessibilityHidden(true)
                }
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            }
        }
    }

    /// The name drawn as its link: person solid, place dotted underline.
    private func name(_ text: String) -> Text {
        Text(
            InkLinkStyle.attributed(
                text, kind: kind == .person ? .person : .place,
                highContrast: contrast == .increased || differentiateWithoutColor))
    }

    /// "**9** geçiş": the number in ink, the word secondary.
    private func countText(_ count: Int) -> Text {
        let number = count.formatted(.number.locale(locale))
        var value = AttributedString(
            String(localized: "\(count) geçiş", bundle: bundle, locale: locale))
        value.foregroundColor = Color.ink.secondaryText
        if let range = value.range(of: number) {
            value[range].foregroundColor = Color.ink.text
            value[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(value)
    }

    @ViewBuilder
    private func row(_ item: SummaryEntityCount) -> some View {
        let isFirst = firsts.contains { $0.id == item.id }
        let spoken = SummaryPresentation.chipLabel(
            name: item.name, count: item.count, isFirst: isFirst, locale: locale)
        let entity = store.content.entities.first(where: { $0.id == item.id })
        let content = HStack(spacing: 12) {
            badge
                .accessibilityHidden(true)
            name(item.name)
                .font(.subheadline)
                .lineLimit(1)
            if isFirst {
                Image(systemName: "sparkle")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.accent)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            countText(item.count)
                .font(.footnote)
                .monospacedDigit()
            if entity != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: TapTarget.minimumLength)
        .padding(.horizontal, InkSpacing.cardPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))

        if let entity {
            NavigationLink {
                EntityView(store: store, entity: entity)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Outlined shapes: a ring for a person, a diamond for a place.
    @ViewBuilder
    private var badge: some View {
        switch kind {
        case .person:
            Circle()
                .strokeBorder(Color.ink.person, lineWidth: 2)
                .frame(width: 12, height: 12)
        case .place:
            Rectangle()
                .strokeBorder(Color.ink.place, lineWidth: 2)
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
                .frame(width: 12, height: 12)
        }
    }
}
