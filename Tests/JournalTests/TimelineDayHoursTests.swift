import Foundation
import Testing

@testable import Journal

@Suite struct TimelineDayHoursTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @Test func defaultsToNineThroughEighteen() {
        #expect(TimelineDayHours.range(for: [], calendar: calendar) == 9...18)
    }

    @Test func expandsForEarlierRecords() {
        let early = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 5))!
        #expect(TimelineDayHours.range(for: [early], calendar: calendar) == 5...18)
    }

    @Test func recordsInsideTheStandardRangeKeepIt() {
        #expect(TimelineDayHours.range(forHours: [10, 17]) == 9...18)
    }

    @Test func expandsForLaterRecords() {
        let late = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
        #expect(TimelineDayHours.range(for: [late], calendar: calendar) == 9...23)
        #expect(TimelineDayHours.range(forHours: [23]) == 9...23)
    }
}
