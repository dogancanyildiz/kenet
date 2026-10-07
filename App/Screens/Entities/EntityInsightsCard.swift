import SwiftUI

struct EntityInsightsCard: View {
    let store: IndexStore
    let entity: EntitySummary
    @Environment(\.clockNow) private var clockNow

    var body: some View {
        let insight = EntityInsights.compute(
            path: entity.id, content: store.content, today: LocalDay.today(at: clockNow()))
        Section {
            SectionHeader(
                title: String(
                    localized: entity.kind == "place" ? "Son ziyaret" : "Son görüşme")
            )
            .inkListRow()
            if let date = insight.lastDay {
                labeled(String(localized: "Son geçiş")) {
                    Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                        .font(.ink.meta)
                        .foregroundStyle(.ink.text)
                }
                .inkListRow()
                ForEach(insight.rows) { row in
                    LinkedTextView(text: row.text, store: store)
                        .inkListRow()
                }
                companions(String(localized: "O gün geçen kişiler"), insight.people)
                companions(String(localized: "O gün geçen konumlar"), insight.places)
                if let first = insight.firstDay {
                    labeled(String(localized: "İlk geçiş")) {
                        Text(LocalDay.instant(for: first), format: .dateTime.day().month().year())
                            .font(.ink.meta)
                            .foregroundStyle(.ink.text)
                    }
                    .inkListRow()
                }
            } else {
                Text("Henüz günlükte geçmedi.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .inkListRow()
            }
            labeled(String(localized: "Son 90 günde")) {
                Text("\(insight.recentDayCount) gün")
                    .font(.ink.value)
                    .foregroundStyle(.ink.text)
            }
            .inkListRow()
            if let interval = insight.averageInterval {
                labeled(String(localized: "Ortalama aralık")) {
                    Text("\(interval.formatted(.number.precision(.fractionLength(0...1)))) gün")
                        .font(.ink.value)
                        .foregroundStyle(.ink.text)
                }
                .inkListRow()
            } else {
                Text("Aralık hesabı için en az iki gün gerekir.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .inkListRow()
            }
            Text("Günlükteki geçişlere dayanır.")
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .inkListRow()
        }
    }

    @ViewBuilder private func companions(_ title: String, _ entities: [EntitySummary]) -> some View {
        if !entities.isEmpty {
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .inkListRow()
            ForEach(entities) { entity in
                NavigationLink {
                    EntityView(store: store, entity: entity)
                } label: {
                    EntityRow(entity: entity)
                }
                .inkListRow()
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
