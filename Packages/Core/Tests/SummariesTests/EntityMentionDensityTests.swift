import Foundation
import Summaries
import Testing
import VaultFormat

struct EntityMentionDensityTests {
    @Test func fixtureCasesMatchDensityComputations() throws {
        let url = fixtureDirectory().appendingPathComponent("summaries/entity-density.json")
        let data = try Data(contentsOf: url)

        struct FixtureCase: Decodable {
            let id: String
            let description: String
            let today: String
            let days: [String]
            let expected: EntityMentionDensity
        }

        let cases = try JSONDecoder().decode([FixtureCase].self, from: data)
        #expect(cases.count == 6)

        for fixture in cases {
            let today = try #require(CalendarDate(fixture.today))
            let days = try fixture.days.map { try #require(CalendarDate($0)) }
            let computed = EntityMentionDensity.compute(days: days, today: today)
            #expect(computed == fixture.expected, Comment(rawValue: fixture.id))
        }
    }

    @Test func twelveMonthBoundaryIncludesStartAndExcludesPriorDay() {
        let today = CalendarDate("2026-10-15")!
        let priorDay = CalendarDate("2025-10-31")!
        let windowStart = CalendarDate("2025-11-01")!

        let computed = EntityMentionDensity.compute(
            days: [priorDay, windowStart, today],
            today: today
        )

        #expect(computed.hasHistory)
        #expect(computed.totalYearDays == 2)
        #expect(computed.months.first?.month == CalendarDate("2025-11-01"))
        #expect(computed.months.first?.count == 1)
        #expect(computed.busiestMonth == CalendarDate("2025-11-01"))
        #expect(computed.busiestMonthCount == 1)
    }

    @Test func olderHistoryWithZeroDaysInYearKeepsHistoryTrue() {
        let today = CalendarDate("2026-10-15")!
        let oldDay = CalendarDate("2025-08-10")!

        let computed = EntityMentionDensity.compute(
            days: [oldDay],
            today: today
        )

        #expect(computed.hasHistory)
        #expect(computed.totalYearDays == 0)
        #expect(computed.busiestMonth == nil)
        #expect(computed.busiestMonthCount == 0)
        #expect(computed.recentDayCount == 0)
        #expect(computed.averageInterval == nil)
    }

    @Test func duplicatesAndFutureDaysAreIgnored() {
        let today = CalendarDate("2026-10-15")!
        let future = CalendarDate("2026-10-16")!
        let day1 = CalendarDate("2026-10-10")!

        let computed = EntityMentionDensity.compute(
            days: [day1, day1, day1, future, today],
            today: today
        )

        #expect(computed.hasHistory)
        #expect(computed.recentDayCount == 2)
        #expect(computed.averageInterval == 5.0)
        #expect(computed.totalYearDays == 2)
        #expect(computed.busiestMonth == CalendarDate("2026-10-01"))
        #expect(computed.busiestMonthCount == 2)
    }

    @Test func emptyTimelineYieldsEmptyDensity() {
        let today = CalendarDate("2026-10-15")!
        let computed = EntityMentionDensity.compute(days: [], today: today)

        #expect(!computed.hasHistory)
        #expect(computed.totalYearDays == 0)
        #expect(computed.busiestMonth == nil)
        #expect(computed.busiestMonthCount == 0)
        #expect(computed.recentDayCount == 0)
        #expect(computed.averageInterval == nil)
        #expect(computed.months.count == 12)
        #expect(computed.recentDays.count == 90)
        #expect(computed.recentDays.last?.isToday == true)
        #expect(computed.recentDays.last?.isMentioned == false)
    }

    @Test func busiestMonthChoosesEarliestOnTie() {
        let today = CalendarDate("2026-10-15")!
        let marchDay = CalendarDate("2026-03-10")!
        let aprilDay = CalendarDate("2026-04-10")!

        let computed = EntityMentionDensity.compute(
            days: [marchDay, aprilDay],
            today: today
        )

        #expect(computed.busiestMonthCount == 1)
        #expect(computed.busiestMonth == CalendarDate("2026-03-01"))
    }
}
