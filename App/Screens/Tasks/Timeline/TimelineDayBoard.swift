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

/// Day-scale timeline (screens.md "Gün ölçeği"): week strip, vertical hour axis with dashed hour
/// lines and timed events in zone cards, the "now" line with its time badge (today only), then
/// the untimed tasks and events under a "Saatsiz" header below the axis. Tasks carry no time of day
/// in the vault format, so every task sits in "Saatsiz".
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
        let untimed = events.filter { $0.time == nil }
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            InkWeekStrip(selection: selection, writtenDays: events.isEmpty ? [] : [LocalDay.instant(for: day)])

            hourAxis(TimelineDayHours.range(forHours: events.compactMap(\.time).map(\.hour)))

            if !tasks.isEmpty || !untimed.isEmpty {
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    SectionHeader(title: String(localized: "Saatsiz"), count: tasks.count + untimed.count)
                    // Zone cards straight on paper: a card never sits inside a card (design.md).
                    ForEach(untimed) { event in eventCard(event) }
                    ForEach(tasks) { task in
                        TimelineTaskCard(task: task, today: today) { selectTask(task) }
                    }
                }
            }
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.vertical, InkSpacing.section)
    }

    private var selection: Binding<Date> {
        Binding(
            get: { LocalDay.instant(for: day) },
            set: { selectDay(LocalDay.today(at: $0)) })
    }

    private func hourAxis(_ hours: ClosedRange<Int>) -> some View {
        let timed = Dictionary(grouping: events.filter { $0.time != nil }) { $0.time!.hour }
        return VStack(spacing: 0) {
            ForEach(Array(hours), id: \.self) { hour in
                HStack(alignment: .top, spacing: 10) {
                    Text(EventTimeFormat.string(hour: hour, minute: 0, locale: locale))
                        .font(.ink.time).foregroundStyle(.ink.secondaryText)
                        .frame(width: timeColumnWidth, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        Line()
                            .stroke(Color.ink.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            .frame(height: 1)
                            .accessibilityHidden(true)
                        ForEach(timed[hour] ?? []) { event in eventCard(event) }
                    }
                }
                .frame(minHeight: hourHeight, alignment: .top)
                .overlay(alignment: .topLeading) {
                    if day == today, currentHour == hour { nowLine }
                }
            }
        }
    }

    private var nowLine: some View {
        HStack(spacing: 6) {
            Text(EventTimeFormat.string(hour: currentHour, minute: currentMinute, locale: locale))
                .font(.ink.meta.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.ink.onAccent)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.ink.accent))
            Rectangle().fill(Color.ink.accent).frame(height: 1.5)
                .accessibilityHidden(true)
        }
        .offset(y: CGFloat(currentMinute) / 60 * hourHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Şimdi"))
    }

    private func eventCard(_ event: EventRow) -> some View {
        Button { selectEvent(event) } label: {
            InkTimelineCard(
                title: event.text.plainText,
                meta: event.time.map { EventTimeFormat.string(for: $0, locale: locale) },
                barColor: TimelineEventColor.color(for: event, store: store),
                kindLabel: String(localized: "Olay"))
        }
        .buttonStyle(.plain)
    }

    private var now: Date { clockNow() }
    private var currentHour: Int { calendar.component(.hour, from: now) }
    private var currentMinute: Int { calendar.component(.minute, from: now) }
}

/// A task in a zone card (Gün and Hafta): project color bar with the project name as text
/// (projectless: `control` and "Projesiz"); a carried-over task adds a 1 pt warning frame and
/// the "Geç" chip, so the cue never rests on color alone.
struct TimelineTaskCard: View {
    let task: TaskRow
    let today: CalendarDate
    let select: () -> Void

    var body: some View {
        let isLate = !task.isClosed && task.due.map { $0 < today } == true
        Button(action: select) {
            InkTimelineCard(
                title: task.text.plainText,
                meta: task.project ?? String(localized: "Projesiz"),
                barColor: ProjectColor.color(for: task.project),
                kindLabel: isLate ? String(localized: "Geç") : nil,
                isCompleted: task.isClosed)
            .overlay {
                if isLate {
                    RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                        .stroke(Color.ink.warning, lineWidth: 1)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Event zone-card bar: person link → `person`, place link → `place`, otherwise `accent`.
@MainActor
enum TimelineEventColor {
    static func color(for event: EventRow, store: IndexStore) -> Color {
        guard let target = event.text.spans.compactMap(\.target).first,
            let entity = store.content.entities.first(where: { $0.id == target })
        else { return .ink.accent }
        return entity.kind == "person" ? .ink.person : entity.kind == "place" ? .ink.place : .ink.accent
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
