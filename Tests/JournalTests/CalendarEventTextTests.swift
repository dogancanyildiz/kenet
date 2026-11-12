import Foundation
import Testing

@testable import Journal

/// Today's calendar row writes the start once: it already sits on the row's left.
struct CalendarEventTextTests {
    private func event(start: (Int, Int, Int), end: (Int, Int, Int), allDay: Bool = false) -> CalendarEvent {
        let calendar = Calendar.current
        func date(_ value: (Int, Int, Int)) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: value.0, hour: value.1, minute: value.2))!
        }
        return CalendarEvent(
            id: "sample", title: "Sample", start: date(start), end: date(end), isAllDay: allDay,
            color: CalendarEventColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    }

    @Test func rowRangeNamesOnlyTheEndOfAnEventEndingTheNextDay() throws {
        let text = CalendarEventText(locale: Locale(identifier: "tr_TR"))
        let overnight = event(start: (11, 23, 20), end: (12, 0, 20))
        let row = try #require(text.rowRange(overnight))
        #expect(row.hasPrefix("Bitiş "))
        #expect(!row.contains("23:20"))
        #expect(row.contains("00:20"))
        // The detail and the person page keep the whole range.
        #expect(text.range(overnight)?.contains("23:20") == true)
    }

    @Test func rowRangeKeepsTheSameDayRangeAndSkipsAllDay() {
        let text = CalendarEventText(locale: Locale(identifier: "tr_TR"))
        let sameDay = event(start: (11, 19, 0), end: (11, 20, 0))
        #expect(text.rowRange(sameDay) == text.range(sameDay))
        #expect(text.rowRange(event(start: (11, 0, 0), end: (12, 0, 0), allDay: true)) == nil)
    }
}
