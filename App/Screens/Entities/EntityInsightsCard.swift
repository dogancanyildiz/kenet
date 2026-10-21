import Summaries
import SwiftUI

struct EntityInsightsCard: View {
    let store: IndexStore
    let entity: EntitySummary
    /// The entity's timeline, queried by the page that hosts the card.
    let timeline: [EntityTimelineDay]
    /// The day of the last encounter, queried with the timeline by the same page.
    let lastDay: DaySummary?
    @Environment(\.clockNow) private var clockNow
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    /// A reload keeps the previous cadences until it answers; a failed one shows its error.
    @State private var cadences = QueryState<[String: PersonCadence]>()
    @State private var cadenceReady = false
    @State private var cadenceError: String?

    var body: some View {
        let today = LocalDay.today(at: clockNow())
        let insight = EntityInsights.compute(
            path: entity.id, timeline: timeline, lastDay: lastDay, entities: store.content.entities,
            today: today)
        let mentions = insight.mentions(locale: locale, timeZone: timeZone)
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
            if let mentions {
                SectionHeader(
                    title: String(localized: "Geçişler"),
                    counter: String(localized: "\(mentions.totalDays) gün")
                )
                .inkListRow()
                EntityMentionChartsView(data: mentions)
                    .inkListRow()
            }
            if entity.kind == "person" { cadenceRows }
            Text("Günlükteki geçişlere dayanır.")
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .inkListRow()
        }
        .task(id: store.lastUpdated) {
            cadences.apply(await QueryOutcome.of { try await store.personCadences() })
            if !Task.isCancelled { cadenceReady = true }
        }
        .preference(key: CadenceReadyKey.self, value: cadenceReady)
    }

    @ViewBuilder private var cadenceRows: some View {
        let today = LocalDay.today(at: clockNow())
        let status = CadenceStatusPresentation(
            cadence: cadences.value?[entity.id] ?? .none, today: today, locale: locale, timeZone: timeZone)
        if let rhythm = status.rhythm {
            Text(verbatim: rhythm)
                .font(.ink.meta)
                .foregroundStyle(.ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .inkListRow()
        }
        if let snooze = status.snooze {
            Text(verbatim: snooze)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .inkListRow()
        }
        if status.showsResume {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: status.paused ?? "")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                Spacer(minLength: 12)
                Button("Sürdür") {
                    Task { cadenceError = await UnseenCadenceCommand.resume(path: entity.id, store: store) }
                }
                .buttonStyle(InkTextButtonStyle())
            }
            .inkListRow()
        }
        if let error = cadenceError ?? cadences.errorText {
            InfoBand(kind: .error, verbatim: error)
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
