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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 68
    @ScaledMetric(relativeTo: .body) private var timeColumnWidth: CGFloat = 48
    /// The hour axis's measured width; `nil` until the first layout.
    @State private var axisWidth: CGFloat?

    var body: some View {
        let untimed = events.filter { $0.time == nil }
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            // iPhone (drawing): each day in its own small box; Mac keeps the carded strip.
            #if os(iOS)
                InkWeekStrip(
                    selection: selection, writtenDays: events.isEmpty ? [] : [LocalDay.instant(for: day)],
                    style: .boxed)
            #else
                InkWeekStrip(selection: selection, writtenDays: events.isEmpty ? [] : [LocalDay.instant(for: day)])
            #endif

            hourAxis(TimelineDayHours.range(forHours: events.compactMap(\.time).map(\.hour)))

            if !tasks.isEmpty || !untimed.isEmpty {
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    SectionHeader(
                        title: PresentationLocalization.string(localized: "Saatsiz", locale: locale),
                        count: tasks.count + untimed.count)
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
                // Accessibility sizes: the hour sits above its cards, which take the row's width. The
                // "now" badge then has no column to sit in: it takes a line of its own above the cards.
                // xxL and xxxL do the same on a narrow screen (320 pt), by the row's own width.
                let isNowHour = day == today && currentHour == hour
                let stacks = Self.stacksHour(width: axisWidth, dynamicTypeSize: dynamicTypeSize)
                let layout = Self.hourLayout(dynamicTypeSize: dynamicTypeSize)
                layout {
                    InkTimeColumn(
                        text: EventTimeFormat.string(hour: hour, minute: 0, locale: locale),
                        minWidth: stacks ? 0 : timeColumnWidth, alignment: .trailing,
                        reservesWidestTime: !stacks)
                    VStack(alignment: .leading, spacing: 6) {
                        Line()
                            .stroke(Color.ink.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            .frame(height: 1)
                            .accessibilityHidden(true)
                        if stacks, isNowHour { nowLine(offset: 0) }
                        ForEach(timed[hour] ?? []) { event in eventCard(event) }
                    }
                }
                .frame(minHeight: hourHeight, alignment: .top)
                .overlay(alignment: .topLeading) {
                    if !stacks, isNowHour { nowLine(offset: CGFloat(currentMinute) / 60 * hourHeight) }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            axisWidth = $0
        }
    }

    /// The hour row's layout, one at every size so a card keeps its identity as the text grows:
    /// the hour above its cards at accessibility sizes, beside them otherwise, and at xxL and xxxL
    /// above them when the row is narrower than ``InkSpacing/narrowPageRowWidth``. Two subviews:
    /// the hour column, the cards.
    static func hourLayout(dynamicTypeSize: DynamicTypeSize) -> AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        let narrow = InkSpacing.timeStackingWidth(
            narrowWidth: InkSpacing.narrowPageRowWidth, dynamicTypeSize: dynamicTypeSize)
        guard let narrow else { return AnyLayout(HStackLayout(alignment: .top, spacing: 10)) }
        return AnyLayout(InkTimeRowLayout(gap: 10, stacksBelowWidth: narrow))
    }

    /// Whether the hour sits above its cards in an axis `width` points wide (`nil`: not measured
    /// yet). The layout decides the same from its own width; this places the "now" line with it.
    static func stacksHour(width: CGFloat?, dynamicTypeSize: DynamicTypeSize) -> Bool {
        if dynamicTypeSize.isAccessibilitySize { return true }
        let narrow = InkSpacing.timeStackingWidth(
            narrowWidth: InkSpacing.narrowPageRowWidth, dynamicTypeSize: dynamicTypeSize)
        guard let narrow, let width else { return false }
        return width < narrow
    }

    private func nowLine(offset: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(EventTimeFormat.string(hour: currentHour, minute: currentMinute, locale: locale))
                .font(.ink.meta.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.ink.onAccent)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.ink.accent))
            Rectangle().fill(Color.ink.accent).frame(height: 1.5)
                .accessibilityHidden(true)
        }
        .offset(y: offset)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Şimdi"))
    }

    private func eventCard(_ event: EventRow) -> some View {
        Button {
            selectEvent(event)
        } label: {
            InkTimelineCard(
                title: event.text.plainText,
                meta: event.time.map { EventTimeFormat.string(for: $0, locale: locale) },
                barColor: TimelineEventColor.color(for: event, store: store),
                kindLabel: PresentationLocalization.string(localized: "Olay", locale: locale))
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
    @Environment(\.locale) private var locale

    var body: some View {
        let isLate = !task.isClosed && task.due.map { $0 < today } == true
        Button(action: select) {
            InkTimelineCard(
                title: task.text.plainText,
                meta: task.project
                    ?? PresentationLocalization.string(localized: "Projesiz", locale: locale),
                barColor: ProjectColor.color(for: task.project),
                kindLabel: isLate
                    ? PresentationLocalization.string(localized: "Geç", locale: locale) : nil,
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
