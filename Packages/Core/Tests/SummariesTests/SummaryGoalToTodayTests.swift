import Foundation
import GoalTracking
import Summaries
import Testing
import VaultFormat
import VaultIndex

/// Goal progress of a running period ends at today like the counts; the target stays the whole period's.
struct SummaryGoalToTodayTests {
    /// Wednesday of the week 5–11 October 2026.
    private let today = CalendarDate("2026-10-07")!

    /// Logs on both sides of today and after the week: Friday 9 October and later have day files already.
    private func input() throws -> SummaryInput {
        func day(_ text: String) -> CalendarDate { CalendarDate(text)! }
        let swim = try #require(
            GoalDefinition(id: "swim", key: "swim", name: "Yüzme", period: .week, kind: .boolean, target: 3))
        let walk = try #require(GoalDefinition(id: "walk", key: "walk", name: "Yürüyüş", period: .day, kind: .boolean))
        let km = try #require(
            GoalDefinition(id: "km", key: "km", name: "Koşu", period: .year, kind: .number, target: 100, unit: "km"))
        let trip = try #require(GoalDefinition(id: "trip", key: "trip", name: "Gezi", period: .year, kind: .milestone))
        return SummaryInput(goals: [
            .init(
                definition: swim,
                logs: ["2026-10-05", "2026-10-06", "2026-10-09", "2026-10-10", "2026-10-12"].map {
                    GoalLog(day: day($0), value: .boolean(true))
                }),
            .init(
                definition: walk,
                logs: ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-11", "2026-10-13"].map {
                    GoalLog(day: day($0), value: .boolean(true))
                }),
            .init(
                definition: km,
                logs: [("2026-03-01", 40.0), ("2026-10-06", 10), ("2026-10-09", 25), ("2026-10-15", 5)].map {
                    GoalLog(day: day($0.0), value: .number($0.1))
                }),
            .init(definition: trip, logs: [GoalLog(day: day("2026-10-09"), value: .boolean(true))]),
        ])
    }

    private func goals(_ period: SummaryPeriod, containing day: CalendarDate, today: CalendarDate?) throws
        -> [String: SummaryGoal]
    {
        let summary = PeriodSummary.compute(period: period, containing: day, data: try input(), today: today)
        return Dictionary(uniqueKeysWithValues: summary.goals.map { ($0.definition.id, $0) })
    }

    @Test func runningPeriodCountsGoalProgressToTodayAgainstTheWholeTarget() throws {
        // Done / target / contribution per goal. Before: swim 4/3 in the week, walk 5/7, km 75, trip done on 9 October.
        let expected: [SummaryPeriod: [String: (done: Double, target: Double, contribution: Double)]] = [
            .week: ["swim": (2, 3, 2), "walk": (3, 7, 3), "km": (50, 100, 10), "trip": (0, 1, 0)],
            // October 2026 touches 5 Monday weeks; 2026 touches 53.
            .month: ["swim": (2, 15, 2), "walk": (3, 31, 3), "km": (50, 100, 10), "trip": (0, 1, 0)],
            .year: ["swim": (2, 159, 2), "walk": (3, 365, 3), "km": (50, 100, 50), "trip": (0, 1, 0)],
        ]
        let data = try input()
        for (period, values) in expected {
            let shown = try goals(period, containing: today, today: today)
            for (id, value) in values {
                let goal = try #require(shown[id])
                let label = Comment(rawValue: "\(period) \(id)")
                #expect(goal.progress.done == value.done, label)
                #expect(goal.progress.target == value.target, label)
                #expect(goal.contribution == value.contribution, label)
                #expect(goal.completionDate == nil, label)
                // The chain is the goal list's on today, in every period.
                let listed = try #require(data.goals.first { $0.definition.id == id })
                #expect(
                    goal.streak
                        == GoalProgress.compute(definition: listed.definition, logs: listed.logs, today: today).streak,
                    label)
            }
            // Nothing was logged in the measured days of the period before.
            #expect(shown["swim"]?.change == 2 && shown["walk"]?.change == 3)
        }
        let week = try goals(.week, containing: today, today: today)
        #expect(week["walk"]?.streak == 3 && week["swim"]?.streak == 0)
        let marked = ["2026-10-05", "2026-10-06", "2026-10-07"].map { CalendarDate($0)! }
        #expect(week["walk"]?.dayMarks.keys.sorted() == marked)
    }

    @Test func endedPeriodCountsItsWholeRangeAndNothingAfter() throws {
        let sunday = CalendarDate("2026-10-11")!
        for later in [CalendarDate("2026-10-20"), sunday, nil] {
            let week = try goals(.week, containing: today, today: later)
            let label = Comment(rawValue: later?.description ?? "no today")
            #expect(week["swim"]?.progress == GoalAmount(done: 4, target: 3), label)
            #expect(week["walk"]?.progress == GoalAmount(done: 5, target: 7), label)
            #expect(week["walk"]?.dayMarks.count == 7, label)
            // A yearly goal reads the year up to the week's last day, not up to today.
            #expect(week["km"]?.progress == GoalAmount(done: 75, target: 100) && week["km"]?.contribution == 35, label)
            #expect(week["trip"]?.completionDate == CalendarDate("2026-10-09"), label)
            #expect(week["trip"]?.contribution == 1, label)
        }
        // A period that has not started is counted whole.
        let coming = try goals(.week, containing: CalendarDate("2026-10-14")!, today: today)
        #expect(coming["swim"]?.progress.done == 1 && coming["walk"]?.progress.done == 1)
    }

    @Test func goalLogOnlyInADayFileToComeLeavesTheRunningWeekEmpty() throws {
        let swim = try #require(
            GoalDefinition(id: "swim", key: "swim", name: "Yüzme", period: .week, kind: .boolean, target: 3))
        let data = SummaryInput(goals: [
            .init(definition: swim, logs: [GoalLog(day: CalendarDate("2026-10-09")!, value: .boolean(true))])
        ])
        #expect(PeriodSummary.compute(period: .week, containing: today, data: data, today: today).isEmpty)
        #expect(!PeriodSummary.compute(period: .week, containing: today, data: data).isEmpty)
    }

    /// From day files through the index: Friday's file is written already, Wednesday is today.
    @Test func dayFileAfterTodayAddsNoProgressThroughTheIndex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["journal", "goals"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try "---\ntype: goal\nname: Spor\nkey: spor\nperiod: week\nkind: boolean\ntarget: 3\n---\n".write(
            to: root.appendingPathComponent("goals/Spor.md"), atomically: true, encoding: .utf8)
        for day in ["2026-10-05", "2026-10-06", "2026-10-09", "2026-10-10"] {
            try "---\ntype: journal\ndate: \(day)\ngoals:\n  spor: true\n---\n".write(
                to: root.appendingPathComponent("journal/\(day).md"), atomically: true, encoding: .utf8)
        }
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let input = try index.summaryInput(from: CalendarDate("2026-09-28")!, to: CalendarDate("2026-10-11")!)
        let running = try #require(
            PeriodSummary.compute(period: .week, containing: today, data: input, today: today).goals.first)
        #expect(running.progress == GoalAmount(done: 2, target: 3) && running.streak == 0)
        let ended = try #require(PeriodSummary.compute(period: .week, containing: today, data: input).goals.first)
        #expect(ended.progress == GoalAmount(done: 4, target: 3) && ended.streak == 1)
    }
}
