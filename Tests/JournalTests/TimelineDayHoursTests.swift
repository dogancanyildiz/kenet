import Foundation
import Testing

@testable import Journal

@Suite struct TimelineDayHoursTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @Test func defaultsToEightThroughTwenty() {
        #expect(TimelineDayHours.range(for: [], calendar: calendar) == 8...20)
    }

    @Test func expandsForEarlierRecords() {
        let early = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 5))!
        #expect(TimelineDayHours.range(for: [early], calendar: calendar) == 5...20)
    }

    @Test func expandsForLaterRecords() {
        let late = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
        #expect(TimelineDayHours.range(for: [late], calendar: calendar) == 8...23)
        #expect(TimelineDayHours.range(forHours: [23]) == 8...23)
    }
}
