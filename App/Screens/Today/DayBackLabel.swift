import SwiftUI
import VaultFormat

/// The short date a page pushed from a past day shows on its back item (unit-tested): day and
/// abbreviated month ("17 Eyl"), with the year when it is not this year's.
enum DayBackLabel {
    static func text(for date: CalendarDate, today: CalendarDate, locale: Locale, calendar: Calendar) -> String {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        var style = Date.FormatStyle(locale: resolved, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)
        if date.year != today.year { style = style.year() }
        return LocalDay.instant(for: date, timeZone: calendar.timeZone).formatted(style)
    }
}
