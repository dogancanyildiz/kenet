import Summaries
import SwiftUI
import VaultFormat

struct EntityInsightsCard: View {
    let store: IndexStore
    let entity: EntitySummary
    /// The entity's timeline, queried by the page that hosts the card.
    let timeline: [EntityTimelineDay]
    /// The day of the last encounter, queried with the timeline by the same page.
    let lastDay: DaySummary?
    /// Opens a companion's page (the hosting page pushes it, outside its list).
    var open: (EntitySummary) -> Void = { _ in }
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
        // Şafak "Son görüşme" card: title and last date on one line, the 12-month bars, the
        // 90-day strip with its one-line note, then that day's text and companions, compact.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if entity.kind == "place" { Text("Son ziyaret") } else { Text("Son görüşme") }
                }
                .font(.headline)
                .foregroundStyle(.ink.text)
                .accessibilityAddTraits(.isHeader)
                // Section title, not a manşet (manşet probes and audits key on this).
                .accessibilityIdentifier(SectionHeader.titleIdentifier)
                Spacer(minLength: 8)
                if let date = insight.lastDay {
                    Text(verbatim: Self.lastLine(date, today: today, locale: locale))
                        .font(.footnote)
                        .foregroundStyle(.ink.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
            if insight.lastDay == nil {
                Text("Henüz günlükte geçmedi.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let mentions {
                EntityMonthlyBarChart(data: mentions)
                Entity90DayStrip(data: mentions, footnote: String(localized: "Günlükteki geçişlere dayanır."))
            } else {
                Text("Günlükteki geçişlere dayanır.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if insight.lastDay != nil {
                lastDayRows(insight)
            }
            if entity.kind == "person" { cadenceRows }
        }
        .task(id: store.lastUpdated) {
            cadences.apply(await QueryOutcome.of { try await store.personCadences() })
            if !Task.isCancelled { cadenceReady = true }
        }
        .preference(key: CadenceReadyKey.self, value: cadenceReady)
    }

    /// "19 Eyl Cmt · 1 gün önce".
    static func lastLine(_ date: CalendarDate, today: CalendarDate, locale: Locale) -> String {
        let day = LocalDay.instant(for: date).formatted(
            .dateTime.day().month(.abbreviated).weekday(.abbreviated).locale(locale))
        guard date.ordinal <= today.ordinal else { return day }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(from: DateComponents(day: date.ordinal - today.ordinal))
        return day + " · " + relative
    }

    /// The last day's own text, the people and places of that day as chips, and the first mention.
    @ViewBuilder private func lastDayRows(_ insight: EntityInsights) -> some View {
        InkCardDivider()
        ForEach(insight.rows) { row in
            LinkedTextView(text: row.text, store: store)
                .font(.subheadline)
        }
        let companions = insight.people + insight.places
        if !companions.isEmpty {
            InkFlowLayout(spacing: 6, lineSpacing: 0) {
                Text("O gün")
                    .font(.footnote)
                    .foregroundStyle(.ink.secondaryText)
                    .frame(minHeight: TapTarget.minimumLength)
                ForEach(companions) { companion in
                    Button {
                        open(companion)
                    } label: {
                        Text(verbatim: companion.name)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(companion.kind == "place" ? Color.ink.place : Color.ink.person)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.ink.well, in: Capsule())
                            .frame(minHeight: TapTarget.minimumLength)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        if let first = insight.firstDay {
            labeled(String(localized: "İlk geçiş")) {
                Text(LocalDay.instant(for: first), format: .dateTime.day().month().year())
                    .font(.ink.meta)
                    .foregroundStyle(.ink.text)
            }
        }
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
        }
        if let snooze = status.snooze {
            Text(verbatim: snooze)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        if let error = cadenceError ?? cadences.errorText {
            InfoBand(kind: .error, verbatim: error)
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
