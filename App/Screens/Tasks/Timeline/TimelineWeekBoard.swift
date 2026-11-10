import SwiftUI
import VaultFormat

/// Hafta scale: seven day columns of zone cards. A task spanning several days shows on each day
/// of its span in the week: the full card on its first day there, a continuation badge on the
/// days after it. Columns are a header and a plain stack (a card never sits inside a card).
struct TimelineWeekBoard: View {
    let store: IndexStore
    let week: [Date]
    let summaries: [DaySummary]
    let rows: [TaskRow]
    let today: CalendarDate
    let selectTask: (TaskRow) -> Void
    let selectEvent: (CalendarDate, EventRow) -> Void

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 190

    var body: some View {
        let days = week.map { LocalDay.today(at: $0) }
        let placements = TimelineWeekPlacement.make(rows: rows, week: days, today: today)
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: InkSpacing.row) {
                ForEach(days, id: \.self) { day in
                    let events = summaries.first(where: { $0.date == day })?.events ?? []
                    dayColumn(day, events: events, tasks: placements[day] ?? [])
                }
            }
            .padding(.horizontal, InkSpacing.margin)
            .padding(.vertical, InkSpacing.section)
        }
    }

    private func dayColumn(
        _ day: CalendarDate, events: [EventRow], tasks: [TimelineWeekPlacement.Entry]
    ) -> some View {
        VStack(alignment: .leading, spacing: InkSpacing.row) {
            HStack {
                Text(dayName(day)).font(.ink.section).foregroundStyle(.ink.text)
                Spacer(minLength: 4)
                Text(verbatim: String(day.day)).font(.ink.value).monospacedDigit()
                    .foregroundStyle(.ink.secondaryText)
            }
            .accessibilityElement(children: .combine)
            ForEach(events) { event in
                Button {
                    selectEvent(day, event)
                } label: {
                    InkTimelineCard(
                        title: event.text.plainText,
                        meta: event.time.map { EventTimeFormat.string(for: $0, locale: locale) },
                        barColor: TimelineEventColor.color(for: event, store: store),
                        kindLabel: String(localized: "Olay"))
                }
                .buttonStyle(.plain)
            }
            ForEach(tasks) { entry in
                if entry.isContinuation {
                    TimelineContinuationBadge(task: entry.row) { selectTask(entry.row) }
                } else {
                    TimelineTaskCard(task: entry.row, today: today) { selectTask(entry.row) }
                }
            }
            if events.isEmpty && tasks.isEmpty {
                Text("Görev veya olay yok.")
                    .font(.ink.meta).foregroundStyle(.ink.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }
        }
        .frame(width: columnWidth, alignment: .topLeading)
    }

    private func dayName(_ day: CalendarDate) -> String {
        LocalDay.instant(for: day).formatted(.dateTime.weekday(.abbreviated).locale(locale))
    }
}

/// Which tasks each day of a week shows (unit-tested). A task shows on every day its span
/// (``TimelineDates/span(on:)``) meets; the first of those days in the week has the full card,
/// the others a continuation. Cancelled tasks stay hidden (screens.md "Durum").
enum TimelineWeekPlacement {
    struct Entry: Identifiable, Equatable {
        let row: TaskRow
        let isContinuation: Bool
        var id: String { row.id }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.row.id == rhs.row.id && lhs.isContinuation == rhs.isContinuation
        }
    }

    static func make(rows: [TaskRow], week: [CalendarDate], today: CalendarDate) -> [CalendarDate: [Entry]] {
        guard let firstDay = week.first, let lastDay = week.last else { return [:] }
        var placements: [CalendarDate: [Entry]] = [:]
        for row in rows where row.rawStatus != "-" {
            guard let span = TimelineDates(row).span(on: today),
                let shown = span.clipped(to: firstDay...lastDay)
            else { continue }
            for day in week where shown.first <= day && day <= shown.last {
                placements[day, default: []].append(Entry(row: row, isContinuation: day != shown.first))
            }
        }
        return placements
    }
}

/// The days after a multi-day task's first day in the week: a neutral bar (the project's color
/// and name stay on the full card), an arrow and the title on one line; the row opens the task.
struct TimelineContinuationBadge: View {
    let task: TaskRow
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color.ink.control)
                    .frame(width: InkSize.timelineBar, height: 16)
                    .accessibilityHidden(true)
                Image(systemName: "arrow.right")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.tertiaryText)
                    .accessibilityHidden(true)
                Text(verbatim: task.text.plainText)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("Sürüyor"))
    }
}
