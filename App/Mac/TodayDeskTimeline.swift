import SwiftUI
import VaultFormat

#if os(macOS)
    /// Vertical hour grid for the Mac Today desk: 09:00–19:00 by default, widened by records;
    /// events and timed tasks as ``InkTimelineCard``; "now" line with time badge on today.
    struct TodayDeskTimeline: View {
        let store: IndexStore
        let plan: TodayDeskPlan
        let day: CalendarDate
        let today: CalendarDate
        var onSelectEvent: (EventRow) -> Void = { _ in }
        var onSelectTask: (TaskRow) -> Void = { _ in }

        @Environment(\.calendar) private var calendar
        @Environment(\.locale) private var locale
        @Environment(\.clockNow) private var clockNow

        @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 68
        @ScaledMetric(relativeTo: .body) private var timeColumnWidth: CGFloat = 48

        var body: some View {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                hourAxis(plan.hourRange)
                if !plan.untimedEvents.isEmpty || !plan.untimedTasks.isEmpty {
                    untimedSection
                }
            }
        }

        private var untimedSection: some View {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: String(localized: "Saatsiz"),
                    count: plan.untimedEvents.count + plan.untimedTasks.count)
                ForEach(plan.untimedEvents) { event in
                    eventCard(event)
                }
                ForEach(plan.untimedTasks) { task in
                    TimelineTaskCard(task: task, today: today) { onSelectTask(task) }
                }
            }
        }

        private func hourAxis(_ hours: ClosedRange<Int>) -> some View {
            let eventsByHour = Dictionary(grouping: plan.timedEvents) { $0.time!.hour }
            let tasksByHour = Dictionary(grouping: plan.timedTasks) { $0.time.hour }
            return VStack(spacing: 0) {
                ForEach(Array(hours), id: \.self) { hour in
                    HStack(alignment: .top, spacing: 10) {
                        Text(EventTimeFormat.string(hour: hour, minute: 0, locale: locale))
                            .font(.ink.time)
                            .foregroundStyle(.ink.secondaryText)
                            .frame(width: timeColumnWidth, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule()
                                .fill(Color.ink.rule)
                                .frame(height: 1)
                                .overlay {
                                    Rectangle()
                                        .stroke(
                                            Color.ink.rule,
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                                        )
                                        .frame(height: 1)
                                }
                                .accessibilityHidden(true)
                            ForEach(eventsByHour[hour] ?? []) { event in
                                eventCard(event)
                            }
                            ForEach(tasksByHour[hour] ?? [], id: \.task.id) { item in
                                timedTaskCard(item.task, time: item.time)
                            }
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
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.ink.accent))
                Rectangle()
                    .fill(Color.ink.accent)
                    .frame(height: 1.5)
                    .accessibilityHidden(true)
            }
            .padding(.leading, timeColumnWidth + 10)
            .offset(y: CGFloat(currentMinute) / 60 * hourHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Şimdi"))
        }

        private func eventCard(_ event: EventRow) -> some View {
            Button {
                onSelectEvent(event)
            } label: {
                InkTimelineCard(
                    title: event.text.plainText,
                    meta: event.time.map { EventTimeFormat.string(for: $0, locale: locale) },
                    barColor: TimelineEventColor.color(for: event, store: store),
                    kindLabel: String(localized: "Olay"))
            }
            .buttonStyle(.plain)
        }

        private func timedTaskCard(_ task: TaskRow, time: EventTime) -> some View {
            let isLate = !task.isClosed && task.due.map { $0 < today } == true
            return Button {
                onSelectTask(task)
            } label: {
                InkTimelineCard(
                    title: TodayDeskPlan.strippingLeadingTime(from: task.text.plainText),
                    meta: EventTimeFormat.string(for: time, locale: locale),
                    barColor: ProjectColor.color(for: task.project),
                    kindLabel: isLate ? String(localized: "Geç") : String(localized: "Görev"),
                    isCompleted: task.isClosed
                )
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

        private var now: Date { clockNow() }
        private var currentHour: Int { calendar.component(.hour, from: now) }
        private var currentMinute: Int { calendar.component(.minute, from: now) }
    }
#endif
