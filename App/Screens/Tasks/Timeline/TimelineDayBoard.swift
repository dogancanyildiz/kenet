import SwiftUI
import VaultFormat

struct TimelineDayRequest: Hashable {
    let date: CalendarDate
    let updated: Date?
    let scale: TimelineModel.Scale
}

struct TimelineWeekRequest: Hashable {
    let date: CalendarDate
    let updated: Date?
    let scale: TimelineModel.Scale
}

/// Day-scale timeline: undated tasks first, followed by the selected day's hourly event axis.
struct TimelineDayBoard: View {
    let store: IndexStore
    let day: CalendarDate
    let today: CalendarDate
    let events: [EventRow]
    let tasks: [TaskRow]
    let selectTask: (TaskRow) -> Void
    let selectEvent: (EventRow) -> Void
    let selectDay: (CalendarDate) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow

    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 68
    @ScaledMetric(relativeTo: .body) private var timeColumnWidth: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            InkWeekStrip(selection: selection, writtenDays: events.isEmpty ? [] : [LocalDay.instant(for: day)])
                .padding(.horizontal, InkSpacing.margin)

            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    SectionHeader(title: String(localized: "Saatsiz"), count: tasks.count)
                    InkCard(padded: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                                let isLate = !task.isClosed && task.due.map { $0 < today } == true
                                Button { selectTask(task) } label: {
                                    InkTimelineCard(
                                        title: task.text.plainText,
                                        meta: task.project ?? String(localized: "Projesiz"),
                                        barColor: isLate
                                            ? .ink.warning : ProjectColor.color(for: task.project),
                                        kindLabel: isLate ? String(localized: "Geç") : nil,
                                        isCompleted: task.isClosed)
                                }
                                .buttonStyle(.plain)
                                .overlay {
                                    if isLate {
                                        RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                                            .stroke(Color.ink.warning, lineWidth: InkStroke.highPriority)
                                    }
                                }
                                .padding(.horizontal, InkSpacing.cardPadding)
                                .padding(.vertical, 6)
                                if index < tasks.count - 1 { InkCardDivider() }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, InkSpacing.margin)
            }

            let timedHours = events.compactMap(\.time).map(\.hour)
            if !timedHours.isEmpty {
                hourAxis(TimelineDayHours.range(forHours: timedHours))
            } else if !events.isEmpty {
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    SectionHeader(title: String(localized: "Saati yok"), count: events.count)
                    ForEach(events) { event in eventCard(event) }
                }
                .padding(.horizontal, InkSpacing.margin)
            } else {
                EmptyState("Bu gün saatli olay yok.")
                    .padding(.horizontal, InkSpacing.margin)
            }
        }
        .padding(.vertical, InkSpacing.section)
    }

    private var selection: Binding<Date> {
        Binding(
            get: { LocalDay.instant(for: day) },
            set: { selectDay(LocalDay.today(at: $0)) })
    }

    private func hourAxis(_ hours: ClosedRange<Int>) -> some View {
        let timed = Dictionary(grouping: events.filter { $0.time != nil }) { $0.time!.hour }
        let untimed = events.filter { $0.time == nil }
        return VStack(alignment: .leading, spacing: InkSpacing.row) {
            if !untimed.isEmpty {
                SectionHeader(title: String(localized: "Saati yok"), count: untimed.count)
                ForEach(untimed) { event in eventCard(event) }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(hours), id: \.self) { hour in
                        HStack(alignment: .top, spacing: 10) {
                            Text(EventTimeFormat.string(hour: hour, minute: 0, locale: locale))
                                .font(.ink.time).foregroundStyle(.ink.secondaryText)
                                .frame(width: timeColumnWidth, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 6) {
                                Rectangle().strokeBorder(
                                    Color.ink.rule,
                                    style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                                    .frame(height: 1)
                                ForEach(timed[hour] ?? []) { event in eventCard(event) }
                            }
                        }
                        .frame(minHeight: hourHeight, alignment: .top)
                        .overlay(alignment: .top) {
                            if day == today, currentHour == hour {
                                HStack(spacing: 6) {
                                    Text(EventTimeFormat.string(hour: currentHour, minute: currentMinute, locale: locale))
                                        .font(.ink.meta.weight(.semibold))
                                        .foregroundStyle(.ink.onAccent)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.ink.accent))
                                    Rectangle().fill(Color.ink.accent).frame(height: 1.5)
                                }
                                .padding(.leading, 40)
                                .offset(y: CGFloat(currentMinute) / 60 * hourHeight)
                                .accessibilityLabel(Text("Şimdi"))
                            }
                        }
                    }
                }
                .padding(.horizontal, InkSpacing.margin)
            }
            .frame(maxHeight: 620)
        }
        .padding(.horizontal, InkSpacing.margin)
    }

    private func eventCard(_ event: EventRow) -> some View {
        Button { selectEvent(event) } label: {
            InkTimelineCard(
                title: event.text.plainText,
                meta: event.time.map { EventTimeFormat.string(for: $0, locale: locale) },
                barColor: eventColor(event), kindLabel: String(localized: "Olay"))
        }
        .buttonStyle(.plain)
    }

    private func eventColor(_ event: EventRow) -> Color {
        guard let target = event.text.spans.compactMap(\.target).first,
            let entity = store.content.entities.first(where: { $0.id == target })
        else { return .ink.accent }
        return entity.kind == "person" ? .ink.person : entity.kind == "place" ? .ink.place : .ink.accent
    }

    private var now: Date { clockNow() }
    private var currentHour: Int { calendar.component(.hour, from: now) }
    private var currentMinute: Int { calendar.component(.minute, from: now) }
}
