import SwiftUI
import VaultFormat

struct TimelineWeekBoard: View {
    let store: IndexStore
    let week: [Date]
    let summaries: [DaySummary]
    let rows: [TaskRow]
    let today: CalendarDate
    let selectTask: (TaskRow) -> Void
    let selectEvent: (CalendarDate, EventRow) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 190

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: InkSpacing.row) {
                ForEach(week, id: \.self) { date in
                    let day = LocalDay.today(at: date)
                    let events = summaries.first(where: { $0.date == day })?.events ?? []
                    // Cancelled tasks stay hidden (screens.md "Durum").
                    let tasks = rows.filter { $0.rawStatus != "-" && ($0.due ?? $0.start) == day }
                    dayColumn(day, events: events, tasks: tasks)
                }
            }
            .padding(.horizontal, InkSpacing.margin)
            .padding(.vertical, InkSpacing.section)
        }
    }

    private func dayColumn(_ day: CalendarDate, events: [EventRow], tasks: [TaskRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dayName(day)).font(.ink.section).foregroundStyle(.ink.text)
                Spacer(minLength: 4)
                Text(verbatim: String(day.day)).font(.ink.value).monospacedDigit()
                    .foregroundStyle(.ink.secondaryText)
            }
            InkCard(padded: false) {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        Button { selectEvent(day, event) } label: {
                            InkTimelineCard(
                                title: event.text.plainText,
                                meta: event.time.map { EventTimeFormat.string(for: $0, locale: locale) },
                                barColor: TimelineEventColor.color(for: event, store: store), kindLabel: String(localized: "Olay"))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    ForEach(tasks) { task in
                        TimelineTaskCard(task: task, today: today) { selectTask(task) }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    if events.isEmpty && tasks.isEmpty {
                        Text("Görev veya olay yok.")
                            .font(.ink.meta).foregroundStyle(.ink.tertiaryText)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
                .frame(width: columnWidth, alignment: .topLeading)
            }
        }
        .frame(width: columnWidth, alignment: .topLeading)
    }

    private func dayName(_ day: CalendarDate) -> String {
        LocalDay.instant(for: day).formatted(.dateTime.weekday(.abbreviated).locale(locale))
    }
}
