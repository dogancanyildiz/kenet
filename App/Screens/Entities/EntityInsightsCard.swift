import SwiftUI

struct EntityInsightsCard: View {
    let store: IndexStore
    let entity: EntitySummary
    @Environment(\.clockNow) private var clockNow
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let insight = EntityInsights.compute(
                path: entity.id, content: store.content, today: LocalDay.today(at: clockNow()))
            Section {
                SectionHeader(
                    title: String(
                        localized: entity.kind == "place" ? "Son ziyaret" : "Son görüşme"))
                if let date = insight.lastDay {
                    labeled(String(localized: "Son geçiş")) {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                            .font(.ink.content)
                            .foregroundStyle(.ink.text)
                    }
                    ForEach(insight.rows) { row in
                        LinkedTextView(text: row.text, store: store)
                    }
                    companions(String(localized: "O gün geçen kişiler"), insight.people)
                    companions(String(localized: "O gün geçen konumlar"), insight.places)
                    if let first = insight.firstDay {
                        labeled(String(localized: "İlk geçiş")) {
                            Text(LocalDay.instant(for: first), format: .dateTime.day().month().year())
                                .font(.ink.content)
                                .foregroundStyle(.ink.text)
                        }
                    }
                } else {
                    Text("Henüz günlükte geçmedi.")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                labeled(String(localized: "Son 90 günde")) {
                    Text("\(insight.recentDayCount) gün")
                        .font(.ink.content)
                        .foregroundStyle(.ink.text)
                }
                if let interval = insight.averageInterval {
                    labeled(String(localized: "Ortalama aralık")) {
                        Text("\(interval.formatted(.number.precision(.fractionLength(0...1)))) gün")
                            .font(.ink.content)
                            .foregroundStyle(.ink.text)
                    }
                } else {
                    Text("Aralık hesabı için en az iki gün gerekir.")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                Text("Günlükteki geçişlere dayanır.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
        }
    }

    @ViewBuilder private func companions(_ title: String, _ entities: [EntitySummary]) -> some View {
        if !entities.isEmpty {
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
            ForEach(entities) { entity in
                NavigationLink {
                    EntityView(store: store, entity: entity)
                } label: {
                    EntityRow(entity: entity)
                }
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder value: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
            Spacer(minLength: 12)
            value()
        }
    }
}
