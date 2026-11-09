import SwiftUI

/// Seven-day week strip (Today, Day, Timeline). Selection is day-granular.
struct InkWeekStrip: View {
    @Binding var selection: Date
    /// Days that have vault writing (compared at start-of-day).
    var writtenDays: Set<Date> = []
    /// When set, days after this instant are drawn but not tappable (Today / past-day strip).
    var latestSelectable: Date? = nil

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let days = Self.daysInWeek(containing: selection, calendar: calendar)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    dayRow(Array(days.prefix(4)))
                    dayRow(Array(days.suffix(3)))
                }
            } else {
                dayRow(days)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func dayRow(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let written = writtenDays.contains { calendar.isDate($0, inSameDayAs: day) }
        let enabled =
            latestSelectable.map {
                TodayWeekStripMath.isSelectable(day, today: $0, calendar: calendar)
            } ?? true
        return Button {
            selection = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text(verbatim: Self.weekdayLetter(day, calendar: calendar, locale: locale))
                    .font(.ink.weekday)
                    .foregroundStyle(Color.ink.tertiaryText)
                Text(verbatim: Self.dayNumber(day, calendar: calendar))
                    .font(.ink.value)
                    .foregroundStyle(
                        enabled
                            ? (selected ? Color.ink.text : Color.ink.secondaryText)
                            : Color.ink.tertiaryText
                    )
                    .monospacedDigit()
                ZStack {
                    if isToday {
                        Circle()
                            .fill(Color.ink.accent)
                            .frame(width: 5, height: 5)
                    } else if written {
                        Circle()
                            .fill(Color.ink.secondaryText)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear.frame(width: 5, height: 5)
                    }
                }
            }
            .frame(width: InkSize.weekDayWidth, height: InkSize.weekDayHeight)
            .background {
                if selected {
                    Capsule().fill(Color.ink.well)
                }
            }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: Self.accessibilityLabel(
            day: day, written: written, calendar: calendar, locale: locale)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Seven dates for the week containing `date`, ordered from the calendar's first weekday.
    static func daysInWeek(containing date: Date, calendar: Calendar) -> [Date] {
        TodayWeekStripMath.daysInWeek(containing: date, calendar: calendar)
    }

    static func weekdayLetter(_ day: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        // Narrow or short weekday in sentence case ("Pzt", "M").
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: day)
    }

    static func dayNumber(_ day: Date, calendar: Calendar) -> String {
        String(calendar.component(.day, from: day))
    }

    static func accessibilityLabel(
        day: Date, written: Bool, calendar: Calendar, locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        var label = formatter.string(from: day)
        if written {
            label +=
                ", "
                + String(
                    localized: "Yazıldı", bundle: PresentationLocalization.bundle(locale),
                    locale: locale)
        }
        return label
    }
}
