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

    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, count: mentions)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entities, id: \.id) { item in
                        row(item)
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
    }

    @ViewBuilder
    private func row(_ item: SummaryEntityCount) -> some View {
        let isFirst = firsts.contains { $0.id == item.id }
        let spoken = SummaryPresentation.chipLabel(
            name: item.name, count: item.count, isFirst: isFirst, locale: locale)
        let content = HStack(spacing: 10) {
            badge
                .accessibilityHidden(true)
            Text(verbatim: item.name)
                .font(.ink.content)
                .foregroundStyle(Color.ink.text)
            if isFirst {
                Image(systemName: "sparkle")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.accent)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Text("\(item.count) geçiş")
                .font(.ink.meta)
                .monospacedDigit()
                .foregroundStyle(Color.ink.secondaryText)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))

        if let entity = store.content.entities.first(where: { $0.id == item.id }) {
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

    @ViewBuilder
    private var badge: some View {
        switch kind {
        case .person:
            Circle()
                .fill(Color.ink.person)
                .frame(width: 8, height: 8)
        case .place:
            Rectangle()
                .fill(Color.ink.place)
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(45))
        }
    }
}
