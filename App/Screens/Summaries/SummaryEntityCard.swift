import Summaries
import SwiftUI

struct SummaryEntityCard: View {
    let store: IndexStore
    let title: String
    let entities: [SummaryEntityCount]
    let mentions: Int
    let first: Int
    let mentionChange: Int
    let firstChange: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            SummaryMetric(title: "Geçişler", value: mentions, change: mentionChange)
            SummaryMetric(title: "İlk kez geçenler", value: first, change: firstChange)
            ForEach(entities, id: \.id) { item in
                HStack(alignment: .firstTextBaseline) {
                    if let entity = store.content.entities.first(where: { $0.id == item.id }) {
                        NavigationLink {
                            EntityView(store: store, entity: entity)
                        } label: {
                            Text(verbatim: item.name)
                                .font(.ink.content)
                                .foregroundStyle(Color.ink.text)
                        }
                    } else {
                        Text(verbatim: item.name)
                            .font(.ink.content)
                            .foregroundStyle(Color.ink.text)
                    }
                    Spacer()
                    Text(item.count.formatted())
                        .font(.ink.value)
                        .foregroundStyle(Color.ink.secondaryText)
                    SummaryChangeBadge(value: Double(item.change))
                }
            }
        }
    }
}
