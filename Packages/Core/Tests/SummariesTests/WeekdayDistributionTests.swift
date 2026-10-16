import Foundation
import Summaries
import Testing
import VaultFormat
import VaultIndex

struct WeekdayDistributionTests {
    @Test func weekdayFixturesMatchHandCountedExpectations() throws {
        let fixtures = fixtureDirectory()
        let cases = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtures.appendingPathComponent("summaries/weekday-distribution.json")))
                as? [[String: Any]])
        #expect(cases.count == 6)
        for fixture in cases {
            let period = try #require((fixture["period"] as? String).flatMap(SummaryPeriod.init(rawValue:)))
            let containing = try #require((fixture["containing"] as? String).flatMap { CalendarDate($0) })
            let today = (fixture["today"] as? String).flatMap { CalendarDate($0) }
            let range = period.bounds(containing: containing)
            let days = try summaryDays(fixture, from: range.lowerBound, to: range.upperBound)
            let result = WeekdayDistribution.compute(
                days: days, period: period, containing: containing, today: today)
            let expected = try #require(fixture["expected"] as? [String: Any])
            #expect(
                try canonical(weekdaySnapshot(result)) == canonical(expected),
                Comment(rawValue: fixture["id"] as? String ?? ""))
        }
    }

    /// Summed across the seven weekdays, written days, measured days and events agree with `PeriodSummary`.
    @Test func totalsMatchThePeriodSummary() throws {
        let fixtures = fixtureDirectory()
        for (vault, period, day, today) in [
            ("sample", SummaryPeriod.month, "2026-09-15", "2026-09-30"),
            ("rhythm", SummaryPeriod.month, "2026-10-07", "2026-10-07"),
            ("rhythm", SummaryPeriod.year, "2026-10-07", "2026-10-07"),
            ("rhythm", SummaryPeriod.year, "2025-03-01", "2026-10-07"),
        ] {
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: fixtures.appendingPathComponent("vaults/" + vault))
            let containing = try #require(CalendarDate(day))
            let now = try #require(CalendarDate(today))
            let range = period.bounds(containing: containing)
            let data = try index.summaryInput(from: range.lowerBound, to: range.upperBound)
            let summary = PeriodSummary.compute(period: period, containing: containing, data: data, today: now)
            let days = try index.summaryDays(from: range.lowerBound, to: range.upperBound)
            let distribution = WeekdayDistribution.compute(
                days: days, period: period, containing: containing, today: now)
            #expect(distribution.entries.map(\.weekday) == Array(0..<7))
            #expect(distribution.writtenDays == summary.counts.writtenDays)
            #expect(distribution.totalDays == summary.units.reduce(0) { $0 + $1.measuredDays })
            #expect(distribution.entries.reduce(0) { $0 + $1.events } == summary.counts.events)
        }
    }

    @Test func entryRatioAndIdentityFollowWrittenAndTotalDays() {
        let zero = WeekdayDistribution.Entry(weekday: 0, writtenDays: 0, totalDays: 0, events: 0)
        #expect(zero.id == 0)
        #expect(zero.ratio == 0)
        let partial = WeekdayDistribution.Entry(weekday: 5, writtenDays: 3, totalDays: 4, events: 10)
        #expect(partial.id == 5)
        #expect(partial.ratio == 0.75)
        let journalOnly = WeekdayDistribution.compute(
            days: [.init(date: CalendarDate("2026-10-04")!, events: 0, hasJournal: true)],
            period: .week,
            containing: CalendarDate("2026-10-04")!
        )
        #expect(journalOnly.leadingWeekday == 6)
        #expect(journalOnly.writtenDays == 1)
    }
}

private func weekdaySnapshot(_ value: WeekdayDistribution) -> [String: Any] {
    [
        "events": value.entries.map(\.events),
        "leadingWeekday": value.leadingWeekday as Any? ?? NSNull(),
        "totalDays": value.entries.map(\.totalDays),
        "writtenDays": value.entries.map(\.writtenDays),
    ]
}
