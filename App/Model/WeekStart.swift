import DateParsing
import Foundation
import VaultFormat

/// Week expressions (`haftaya`, `next week`, `haftaya salı`) follow the user's calendar. Quick entry,
/// the App Intent and the task menu all parse through here, so a typed expression and the menu's
/// "Haftaya" give the same day on every calendar.
enum WeekStart {
    /// The parser knows a Monday and a Sunday week; any other first weekday reads as Sunday.
    static func isMonday(in calendar: Calendar) -> Bool { calendar.firstWeekday == 2 }

    static func date(
        _ text: String, today: CalendarDate, language: [DateParsing.Language], calendar: Calendar
    ) -> DateParse? {
        DateExpressionParser.parse(
            text, today: today, language: language, weekStartsOnMonday: isMonday(in: calendar))
    }

    static func analysis(
        _ text: String, today: CalendarDate, language: [DateParsing.Language], suppressedRanges: [Range<Int>],
        calendar: Calendar
    ) -> QuickEntryAnalysis {
        QuickEntryAnalysis.analyze(
            text, today: today, language: language, suppressedRanges: suppressedRanges,
            weekStartsOnMonday: isMonday(in: calendar))
    }
}
