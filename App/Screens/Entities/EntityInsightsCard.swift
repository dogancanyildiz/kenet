import SwiftUI

struct EntityInsightsCard: View {
    let store: IndexStore
    let entity: EntitySummary
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let insight = EntityInsights.compute(
                path: entity.id, content: store.content, today: LocalDay.today(at: context.date))
            Section(entity.kind == "place" ? LocalizedStringKey("Son ziyaret") : LocalizedStringKey("Son görüşme")) {
                if let date = insight.lastDay {
                    LabeledContent("Son geçiş") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                    }
                    ForEach(insight.rows) { row in
                        LinkedTextView(text: row.text, store: store)
                    }
                    companions("O gün geçen kişiler", insight.people)
                    companions("O gün geçen konumlar", insight.places)
                    if let first = insight.firstDay {
                        LabeledContent("İlk geçiş") {
                            Text(LocalDay.instant(for: first), format: .dateTime.day().month().year())
                        }
                    }
                } else {
                    Text("Henüz günlükte geçmedi.").foregroundStyle(.secondary)
                }
                LabeledContent("Son 90 günde") { Text("\(insight.recentDayCount) gün") }
                if let interval = insight.averageInterval {
                    LabeledContent("Ortalama aralık") {
                        Text("\(interval.formatted(.number.precision(.fractionLength(0...1)))) gün")
                    }
                } else {
                    Text("Aralık hesabı için en az iki gün gerekir.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Günlükteki geçişlere dayanır.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func companions(_ title: LocalizedStringKey, _ entities: [EntitySummary]) -> some View {
        if !entities.isEmpty {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(entities) { entity in
                NavigationLink {
                    EntityView(store: store, entity: entity)
                } label: {
                    EntityRow(entity: entity)
                }
            }
        }
    }
}
