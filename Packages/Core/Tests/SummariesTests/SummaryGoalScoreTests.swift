import GoalTracking
import Summaries
import Testing
import VaultFormat

struct SummaryGoalScoreTests {
    /// Done every day from 1 September to 7 October 2026, except Sunday 4 October.
    private func input() throws -> SummaryInput {
        let daily = try #require(GoalDefinition(id: "water", key: "water", name: "Su", period: .day, kind: .boolean))
        let weekly = try #require(
            GoalDefinition(id: "sport", key: "sport", name: "Spor", period: .week, kind: .boolean, target: 3))
        let first = CalendarDate("2026-09-01")!
        let missed = CalendarDate("2026-10-04")!
        let logs = (0..<37).compactMap { first.addingDays($0) }.filter { $0 != missed }
            .map { GoalLog(day: $0, value: .boolean(true)) }
        return SummaryInput(goals: [.init(definition: daily, logs: logs), .init(definition: weekly, logs: logs)])
    }

    private func score(week day: String, today: String?) throws -> Int? {
        let summary = PeriodSummary.compute(
            period: .week, containing: try #require(CalendarDate(day)), data: try input(),
            today: try today.map { try #require(CalendarDate($0)) })
        return try #require(summary.goals.first { $0.definition.id == "water" }).score
    }

    @Test func runningPeriodIsMeasuredOnTodayNotOnDaysToCome() throws {
        // Wednesday of the week 5–11 October. 8 September–7 October: 29 of 30.
        #expect(try score(week: "2026-10-07", today: "2026-10-07") == 96)
        // The same number the goal list shows that day.
        let goal = try #require(try input().goals.first { $0.definition.id == "water" })
        let listed = GoalProgress.compute(
            definition: goal.definition, logs: goal.logs, today: CalendarDate("2026-10-07")!)
        #expect(listed.score == 96)
        // Thursday, not done yet: today stays out, the window still ends on Wednesday.
        #expect(try score(week: "2026-10-08", today: "2026-10-08") == 96)
        // A week that has not started is measured on today as well.
        #expect(try score(week: "2026-10-14", today: "2026-10-07") == 96)
    }

    @Test func endedPeriodCountsItsMissedLastDay() throws {
        // Week 28 September–4 October, Sunday missed. 5 September–4 October: 29 of 30.
        #expect(try score(week: "2026-10-01", today: "2026-10-07") == 96)
        // Without today the period is taken as ended: 12 September–11 October holds 25 done days.
        #expect(try score(week: "2026-10-07", today: nil) == 83)
    }

    @Test func onlyDailyGoalsCarryAScore() throws {
        let summary = PeriodSummary.compute(
            period: .week, containing: CalendarDate("2026-10-07")!, data: try input(), today: CalendarDate("2026-10-07")
        )
        #expect(try #require(summary.goals.first { $0.definition.id == "sport" }).score == nil)
        let goals = try input().goals
        let end = CalendarDate("2026-10-07")!
        #expect(GoalProgress.score(definition: goals[1].definition, logs: goals[1].logs, through: end) == nil)
        #expect(GoalProgress.score(definition: goals[0].definition, logs: [], through: end) == nil)
        // No day is measured before the first log.
        #expect(
            GoalProgress.score(
                definition: goals[0].definition, logs: goals[0].logs, through: CalendarDate("2026-08-31")!)
                == nil)
        #expect(
            GoalProgress.score(
                definition: goals[0].definition, logs: goals[0].logs, through: CalendarDate("2026-09-01")!)
                == 100)
    }
}
