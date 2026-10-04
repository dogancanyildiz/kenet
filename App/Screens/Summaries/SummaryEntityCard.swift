import Summaries
import SwiftUI

struct SummaryEntityCard: View {
    let store: IndexStore
    let title: LocalizedStringKey
    let entities: [SummaryEntityCount]
    let mentions: Int
    let first: Int
    let mentionChange: Int
    let firstChange: Int
    var body: some View {
        GroupBox(title) {
            VStack(spacing: 10) {
                SummaryMetric(title: "Geçişler", value: mentions, change: mentionChange)
                SummaryMetric(title: "İlk kez geçenler", value: first, change: firstChange)
                ForEach(entities, id: \.id) { item in
                    HStack {
                        if let entity = store.content.entities.first(where: { $0.id == item.id }) {
                            NavigationLink {
                                EntityView(store: store, entity: entity)
                            } label: {
                                Text(verbatim: item.name)
                            }
                        } else {
                            Text(verbatim: item.name)
                        }
                        Spacer()
                        Text(item.count.formatted())
                        SummaryChangeBadge(value: Double(item.change))
                    }
                }
            }.padding(.top, 8)
        }
    }
}
