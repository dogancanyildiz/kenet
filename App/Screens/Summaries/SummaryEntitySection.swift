import Summaries
import SwiftUI

/// The top five people or places as name chips; each chip opens its page. A sparkle marks a name
/// first mentioned in the period, and one line lists every such name, the top five or not.
struct SummaryEntitySection: View {
    let store: IndexStore
    let title: String
    let entities: [SummaryEntityCount]
    let mentions: Int
    let firsts: [SummaryFirstMention]
    let kind: SummaryInput.Entity.Kind
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, count: mentions)
            InkFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(entities, id: \.id) { item in
                    chip(item)
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

    @ViewBuilder
    private func chip(_ item: SummaryEntityCount) -> some View {
        let isFirst = firsts.contains { $0.id == item.id }
        let spoken = SummaryPresentation.chipLabel(name: item.name, count: item.count, isFirst: isFirst, locale: locale)
        let label = TagChip(title: item.name, systemImage: isFirst ? "sparkle" : nil, count: item.count)
            .accessibilityLabel(Text(verbatim: spoken))
        if let entity = store.content.entities.first(where: { $0.id == item.id }) {
            NavigationLink {
                EntityView(store: store, entity: entity)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}
