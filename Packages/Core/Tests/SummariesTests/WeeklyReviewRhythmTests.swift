import Foundation
import Summaries
import Testing
import VaultFormat
import VaultIndex

struct WeeklyReviewRhythmTests {
    @Test func rhythmFixturesMatchHandCountedExpectations() throws {
        let cases = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtureDirectory().appendingPathComponent("summaries/weekly-rhythm.json")))
                as? [[String: Any]])
        #expect(cases.count == 5)
        for fixture in cases {
            let range = try dates(fixture["range"])
            let previous = try dates(fixture["previousRange"])
            let today = (fixture["today"] as? String).flatMap { CalendarDate($0) }
            let days = try summaryDays(fixture, from: previous.lowerBound, to: range.upperBound)
            let result = WeeklyReviewRhythm.compute(days: days, range: range, previousRange: previous, today: today)
            let expected = try #require(fixture["expected"] as? [String: Any])
            #expect(
                try canonical(rhythmSnapshot(result)) == canonical(expected),
                Comment(rawValue: fixture["id"] as? String ?? ""))
        }
    }

    /// On a Monday week the rhythm's change is the Özetler week's: both count up to the same weekday.
    @Test func mondayWeekMatchesTheSummaryWeek() throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: fixtureDirectory().appendingPathComponent("vaults/rhythm"))
        for today in ["2026-10-07", "2026-10-11", "2026-10-04"] {
            let now = try #require(CalendarDate(today))
            let range = SummaryPeriod.week.bounds(containing: now)
            let previous = try #require(SummaryPeriod.week.previous(containing: now))
            let data = try index.summaryInput(from: previous.lowerBound, to: range.upperBound)
            let summary = PeriodSummary.compute(period: .week, containing: now, data: data, today: now)
            let rhythm = WeeklyReviewRhythm.compute(days: data.days, range: range, previousRange: previous, today: now)
            #expect(rhythm.events == summary.counts.events, Comment(rawValue: today))
            #expect(rhythm.previousEvents == summary.previous.events, Comment(rawValue: today))
            #expect(rhythm.isRunning == summary.isRunning, Comment(rawValue: today))
            #expect(rhythm.days.map(\.events) == summary.units.map(\.events), Comment(rawValue: today))
        }
    }
}

private func dates(_ value: Any?) throws -> ClosedRange<CalendarDate> {
    let pair = try #require(value as? [String])
    let lower = try #require(pair.first.flatMap { CalendarDate($0) })
    let upper = try #require(pair.last.flatMap { CalendarDate($0) })
    return lower...upper
}

private func rhythmSnapshot(_ value: WeeklyReviewRhythm) -> [String: Any] {
    [
        "days": value.days.map {
            [
                "date": $0.date.description, "events": $0.events, "previousEvents": $0.previousEvents,
                "writing": $0.writing.rawValue,
            ] as [String: Any]
        },
        "events": value.events, "previousEvents": value.previousEvents, "change": value.change,
        "isRunning": value.isRunning,
    ]
}
