import SwiftUI

/// Seven-day week strip (Today, Day, Timeline). Selection is day-granular.
struct InkWeekStrip: View {
    @Binding var selection: Date
    /// Days that have vault writing (compared at start-of-day).
    var writtenDays: Set<Date> = []
    /// Event counts per day (start-of-day keys), spoken by VoiceOver ("…, 3 olay").
    var eventCounts: [Date: Int] = [:]
    /// When set, days after this instant are drawn but not tappable (Today / past-day strip).
    var latestSelectable: Date? = nil
    /// `.boxed`: every day is its own small card and the strip has no card around it (drawing:
    /// timeline Day scale). `.card` (default): one card around the seven days (Today, day screen).
    var style: InkWeekStripChrome.StripStyle = .card

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var dayWidth = InkSize.weekDayWidth
    @ScaledMetric(relativeTo: .body) private var dayHeight = InkSize.weekDayHeight

    private var weekdayFormatter: DateFormatter {
        Self.makeFormatter(template: "EEE", calendar: calendar, locale: locale)
    }

    private var accessibilityFormatter: DateFormatter {
        Self.makeFormatter(template: "EEEE d MMMM", calendar: calendar, locale: locale)
    }

    var body: some View {
        let days = Self.daysInWeek(containing: selection, calendar: calendar)
        let weekday = weekdayFormatter
        let spoken = accessibilityFormatter
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    dayRow(Array(days.prefix(4)), weekday: weekday, spoken: spoken)
                    dayRow(Array(days.suffix(3)), weekday: weekday, spoken: spoken)
                }
            } else {
                dayRow(days, weekday: weekday, spoken: spoken)
            }
        }
        .padding(style == .card ? InkWeekStripChrome.inset : 0)
        .background {
            // The strip is its own translucent card over the glow (drawing: Today, day screen).
            if style == .card {
                stripCard
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var stripCard: some View {
        RoundedRectangle(cornerRadius: InkCorner.lg, style: .continuous)
            .fill(Color.ink.surface.opacity(reduceTransparency ? 1 : 0.72))
            .overlay {
                RoundedRectangle(cornerRadius: InkCorner.lg, style: .continuous)
                    .strokeBorder(Color.ink.line, lineWidth: 0.5)
            }
    }

    private func dayRow(
        _ days: [Date], weekday: DateFormatter, spoken: DateFormatter
    ) -> some View {
        HStack(spacing: style == .boxed ? InkWeekStripChrome.boxGap : 0) {
            ForEach(days, id: \.self) { day in
                dayCell(day, weekday: weekday, spoken: spoken)
            }
        }
    }

    @ViewBuilder private func dayCell(
        _ day: Date, weekday: DateFormatter, spoken: DateFormatter
    ) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let written = writtenDays.contains { calendar.isDate($0, inSameDayAs: day) }
        let events = eventCounts.first { calendar.isDate($0.key, inSameDayAs: day) }?.value ?? 0
        let enabled =
            latestSelectable.map {
                TodayWeekStripMath.isSelectable(day, today: $0, calendar: calendar)
            } ?? true
        let label = Text(
            verbatim: Self.accessibilityLabel(
                day: day, isToday: isToday, written: written, eventCount: events,
                formatter: spoken, locale: locale))
        let face = dayFace(
            day, weekday: weekday, selected: selected, isToday: isToday, written: written,
            enabled: enabled)
        // A day not yet selectable is plain text in tertiary color, not a disabled button: the
        // system fades a disabled plain button below 4.5:1 (accessibility audit: contrast).
        if enabled {
            Button {
                selection = calendar.startOfDay(for: day)
            } label: {
                face
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        }
    }

    private func dayFace(
        _ day: Date, weekday: DateFormatter, selected: Bool, isToday: Bool, written: Bool,
        enabled: Bool
    ) -> some View {
        let style = InkWeekStripChrome.CellStyle.resolve(selected: selected, isToday: isToday)
        let hasMark = written || eventCount(on: day) > 0
        return VStack(spacing: 4) {
            Text(verbatim: weekday.string(from: day))
                .font(.ink.weekday)
                .foregroundStyle(
                    enabled ? (style == .filled ? Color.ink.paper : Color.ink.secondaryText) : Color.ink.tertiaryText)
            Text(verbatim: Self.dayNumber(day, calendar: calendar))
                .font(.ink.value.weight(.semibold))
                .foregroundStyle(numberColor(style: style, isToday: isToday, enabled: enabled))
                .monospacedDigit()
            // One dot under every day with writing or events; today's dot is accent.
            Circle()
                .fill(dotColor(style: style, isToday: isToday))
                .frame(width: 4, height: 4)
                .opacity(hasMark || isToday ? 1 : 0)
                .frame(height: 5)
        }
        .frame(minWidth: dayWidth, minHeight: dayHeight)
        .background {
            switch style {
            case .filled:
                RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                    .fill(Color.ink.text)
            case .framed:
                RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                    .fill(Color.ink.paper)
                    .overlay {
                        RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                            .strokeBorder(Color.ink.line, lineWidth: 1)
                    }
            case .plain:
                if self.style == .boxed {
                    RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                        .fill(Color.ink.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                                .strokeBorder(Color.ink.rule, lineWidth: 0.5)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func eventCount(on day: Date) -> Int {
        eventCounts.first { calendar.isDate($0.key, inSameDayAs: day) }?.value ?? 0
    }

    private func numberColor(style: InkWeekStripChrome.CellStyle, isToday: Bool, enabled: Bool) -> Color {
        guard enabled else { return Color.ink.tertiaryText }
        switch style {
        case .filled: return Color.ink.paper
        case .framed: return Color.ink.text
        case .plain: return isToday ? Color.ink.accent : Color.ink.text
        }
    }

    private func dotColor(style: InkWeekStripChrome.CellStyle, isToday: Bool) -> Color {
        if style == .filled { return Color.ink.paper }
        return isToday ? Color.ink.accent : Color.ink.secondaryText
    }

    /// Seven dates for the week containing `date`, ordered from the calendar's first weekday.
    nonisolated static func daysInWeek(containing date: Date, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let first = calendar.firstWeekday
        let delta = (weekday - first + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -delta, to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    nonisolated static func dayNumber(_ day: Date, calendar: Calendar) -> String {
        String(calendar.component(.day, from: day))
    }

    /// "20 Eylül Pazar, bugün, 3 olay" (screens.md). A written day without events says
    /// "yazıldı" instead of the count; lowercase keys because the words sit mid-sentence.
    nonisolated static func accessibilityLabel(
        day: Date, isToday: Bool, written: Bool, eventCount: Int = 0, formatter: DateFormatter,
        locale: Locale
    ) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        var parts = [formatter.string(from: day)]
        if isToday {
            parts.append(String(localized: "bugün", bundle: bundle, locale: locale))
        }
        if eventCount > 0 {
            parts.append(String(localized: "\(eventCount) olay", bundle: bundle, locale: locale))
        } else if written {
            parts.append(String(localized: "yazıldı", bundle: bundle, locale: locale))
        }
        return parts.joined(separator: ", ")
    }

    /// Back-compat for tests that pass calendar/locale without a formatter.
    nonisolated static func accessibilityLabel(
        day: Date, written: Bool, calendar: Calendar, locale: Locale, isToday: Bool = false,
        eventCount: Int = 0
    ) -> String {
        let formatter = makeFormatter(template: "EEEE d MMMM", calendar: calendar, locale: locale)
        let today = isToday || calendar.isDateInToday(day)
        return accessibilityLabel(
            day: day, isToday: today, written: written, eventCount: eventCount,
            formatter: formatter, locale: locale)
    }

    nonisolated static func makeFormatter(template: String, calendar: Calendar, locale: Locale)
        -> DateFormatter
    {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

/// Week strip drawing rules (unit-tested).
enum InkWeekStripChrome {
    /// Gap between the strip card's edge and the day cells.
    static let inset: CGFloat = 4
    /// Gap between day boxes in the boxed strip.
    static let boxGap: CGFloat = 6

    enum StripStyle: Equatable, Sendable {
        /// One card around the seven days.
        case card
        /// Every day its own small card.
        case boxed
    }

    enum CellStyle: Equatable, Sendable {
        /// Selected past or future day: text-colored cell, paper text (day screen).
        case filled
        /// Selected today: paper cell with a line (Today).
        case framed
        /// Not selected.
        case plain

        static func resolve(selected: Bool, isToday: Bool) -> Self {
            guard selected else { return .plain }
            return isToday ? .framed : .filled
        }
    }
}
