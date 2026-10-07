import Testing
import VaultFormat

@testable import DateParsing

@Test(arguments: [("2026-10-03", 5), ("2000-02-29", 1), ("1900-03-01", 3), ("0100-01-01", 4), ("2026-10-05", 0)])
func knownWeekdays(_ input: (String, Int)) throws {
    #expect(DateCalendar.weekday(try #require(CalendarDate(input.0))) == input.1)
}

@Test func calendarShiftsRoundTripAndRespectBounds() throws {
    let dates = ["0100-01-01", "1900-02-28", "2000-02-29", "2026-12-31", "9999-12-31"]
    for source in dates {
        let date = try #require(CalendarDate(source))
        for shift in [-366, -31, -1, 0, 1, 31, 366] {
            if let changed = DateCalendar.adding(shift, to: date) {
                #expect(DateCalendar.adding(-shift, to: changed) == date)
            }
        }
    }
    #expect(DateCalendar.adding(-1, to: CalendarDate("0100-01-01")!) == nil)
    #expect(DateCalendar.adding(1, to: CalendarDate("9999-12-31")!) == nil)
    #expect(DateCalendar.adding(Int.max, to: CalendarDate("2026-10-03")!) == nil)
}
