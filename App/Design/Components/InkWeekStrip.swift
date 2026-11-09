import SwiftUI

/// Seven-day week strip (Today, Day, Timeline). Selection is day-granular.
struct InkWeekStrip: View {
    @Binding var selection: Date
    /// Days that have vault writing (compared at start-of-day).
    var writtenDays: Set<Date> = []

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        .accessibilityElement(children: .contain)
    }

    private func dayRow(
        _ days: [Date], weekday: DateFormatter, spoken: DateFormatter
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayCell(day, weekday: weekday, spoken: spoken)
            }
        }
    }

    private func dayCell(
        _ day: Date, weekday: DateFormatter, spoken: DateFormatter
    ) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let written = writtenDays.contains { calendar.isDate($0, inSameDayAs: day) }
        return Button {
            selection = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text(verbatim: weekday.string(from: day))
                    .font(.ink.weekday)
                    .foregroundStyle(Color.ink.secondaryText)
                Text(verbatim: Self.dayNumber(day, calendar: calendar))
                    .font(.ink.value)
                    .foregroundStyle(selected ? Color.ink.text : Color.ink.secondaryText)
                    .monospacedDigit()
                HStack(spacing: 3) {
                    if isToday {
                        Circle()
                            .fill(Color.ink.accent)
                            .frame(width: 5, height: 5)
                    }
                    if written {
                        Circle()
                            .fill(Color.ink.secondaryText)
                            .frame(width: 4, height: 4)
                    }
                    if !isToday && !written {
                        Color.clear.frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(minWidth: dayWidth, minHeight: dayHeight)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: InkCorner.md, style: .continuous)
                        .fill(Color.ink.well)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(
                verbatim: Self.accessibilityLabel(
                    day: day, isToday: isToday, written: written,
                    formatter: spoken, locale: locale))
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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

    nonisolated static func accessibilityLabel(
        day: Date, isToday: Bool, written: Bool, formatter: DateFormatter, locale: Locale
    ) -> String {
        var parts = [formatter.string(from: day)]
        if isToday {
            parts.append(
                String(
                    localized: "Bugün", bundle: PresentationLocalization.bundle(locale),
                    locale: locale))
        }
        if written {
            parts.append(
                String(
                    localized: "Yazıldı", bundle: PresentationLocalization.bundle(locale),
                    locale: locale))
        }
        return parts.joined(separator: ", ")
    }

    /// Back-compat for tests that pass calendar/locale without a formatter.
    nonisolated static func accessibilityLabel(
        day: Date, written: Bool, calendar: Calendar, locale: Locale, isToday: Bool = false
    ) -> String {
        let formatter = makeFormatter(template: "EEEE d MMMM", calendar: calendar, locale: locale)
        let today = isToday || calendar.isDateInToday(day)
        return accessibilityLabel(
            day: day, isToday: today, written: written, formatter: formatter, locale: locale)
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
