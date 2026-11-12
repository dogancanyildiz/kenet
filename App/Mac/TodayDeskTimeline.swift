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
        /// Tasks being written as done right now; their box takes no second click.
        var completingTaskIDs: Set<String> = []
        /// Completes a task the way the day page's task row does (file first, then the index).
        /// `nil` (vault not writable) leaves the boxes as marks only.
        var onCompleteTask: ((TaskRow) -> Void)? = nil

        @Environment(\.calendar) private var calendar
        @Environment(\.locale) private var locale
        @Environment(\.clockNow) private var clockNow

        @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 68
        @ScaledMetric(relativeTo: .body) private var timeColumnWidth: CGFloat = 48
        @ScaledMetric(relativeTo: .body) private var cardPadding = InkSpacing.cardPadding
        @ScaledMetric(relativeTo: .body) private var boxSide = InkSize.taskBox
        @State private var rowHeights: [Int: CGFloat] = [:]

        /// Timed records only: the day page's own task and event lists keep the untimed ones
        /// (``TodayDeskPlan/dayListEvents``, ``TodayDeskPlan/dayListTaskRows(_:)``).
        var body: some View {
            hourAxis(plan.hourRange)
        }

        private func hourAxis(_ hours: ClosedRange<Int>) -> some View {
            let cardsByHour = plan.gridCardsByHour
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
                            ForEach(cardsByHour[hour] ?? [], id: \.gridID) { card in
                                switch card {
                                case .event(let event):
                                    eventCard(event)
                                case .task(let task, let time, let box):
                                    timedTaskCard(task, time: time, box: box)
                                }
                            }
                        }
                    }
                    .frame(minHeight: hourHeight, alignment: .top)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TodayDeskHourHeightKey.self,
                                value: [hour: geo.size.height])
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if day == today, currentHour == hour {
                            nowLine(rowHeight: rowHeights[hour] ?? hourHeight)
                        }
                    }
                }
            }
            .onPreferenceChange(TodayDeskHourHeightKey.self) { rowHeights = $0 }
        }

        private func nowLine(rowHeight: CGFloat) -> some View {
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
            .offset(y: CGFloat(currentMinute) / 60 * rowHeight)
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
                    kindLabel: PresentationLocalization.string(localized: "Olay", locale: locale))
            }
            .buttonStyle(.plain)
        }

        private func timedTaskCard(_ task: TaskRow, time: EventTime, box: TaskBoxState) -> some View {
            let isLate = !box.isCompleted && task.due.map { $0 < today } == true
            let projectLabel = task.project?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = DaySchedulePresentation.strippingLeadingTime(from: task.text.plainText)
            let kindLabel: String = {
                if isLate, let due = task.due {
                    return TodayPresentation.carriedOverDate(
                        due, today: today, locale: locale, calendar: calendar)
                }
                if let projectLabel, !projectLabel.isEmpty { return projectLabel }
                return PresentationLocalization.string(localized: "Görev", locale: locale)
            }()
            // The box sits over the card, not inside its button: a click on it completes the task
            // and never opens the editor; the rest of the card does.
            return Button {
                onSelectTask(task)
            } label: {
                InkTimelineCard(
                    title: title,
                    meta: EventTimeFormat.string(for: time, locale: locale),
                    barColor: ProjectColor.color(for: task.project),
                    kindLabel: kindLabel,
                    isCompleted: box.isCompleted,
                    leadingAccessoryWidth: boxSide + 10
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
            .overlay(alignment: .topLeading) {
                completionBox(task, title: title, box: box)
                    .padding(InkTimelineCard.accessoryInset(padding: cardPadding))
            }
        }

        @ViewBuilder
        private func completionBox(_ task: TaskRow, title: String, box: TaskBoxState) -> some View {
            if box.isCompleted || box.isCancelled {
                TaskBox(state: box, isDecorative: true)
            } else {
                let isBusy = completingTaskIDs.contains(task.id)
                TaskBox(
                    state: box,
                    action: onCompleteTask.flatMap { complete in isBusy ? nil : { complete(task) } },
                    accessibilityLabel: "Tamamla, \(title)"
                )
                .accessibilityIdentifier(Self.taskBoxIdentifier)
            }
        }

        /// The grid task card's completion box (hosted tests find it by this).
        static let taskBoxIdentifier = "today.desk.taskBox"

        private var now: Date { clockNow() }
        private var currentHour: Int { calendar.component(.hour, from: now) }
        private var currentMinute: Int { calendar.component(.minute, from: now) }
    }

    extension TodayDeskPlan.GridCard {
        /// Stable identity within one hour's cards (an event and a task may share a number).
        fileprivate var gridID: String {
            switch self {
            case .event(let event): "event-\(event.id)"
            case .task(let task, _, _): "task-\(task.id)"
            }
        }
    }

    private struct TodayDeskHourHeightKey: PreferenceKey {
        static let defaultValue: [Int: CGFloat] = [:]
        static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }
#endif
