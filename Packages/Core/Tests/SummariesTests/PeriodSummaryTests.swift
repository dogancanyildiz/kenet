import Foundation
import GoalTracking
import Summaries
import Testing
import VaultFormat
import VaultIndex

struct PeriodSummaryTests {
    @Test func sampleFixturesMatchHandCountedExpectations() throws {
        let fixtures = fixtureDirectory()
        let cases = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtures.appendingPathComponent("summaries/cases.json"))) as? [[String: Any]])
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: fixtures.appendingPathComponent("vaults/sample"))
        for fixture in cases {
            let periodText = try #require(fixture["period"] as? String)
            let dayText = try #require(fixture["containing"] as? String)
            let period = try #require(SummaryPeriod(rawValue: periodText))
            let day = try #require(CalendarDate(dayText))
            let bounds = period.bounds(containing: day)
            let first = period.previous(containing: day)?.lowerBound ?? bounds.lowerBound
            let summary = PeriodSummary.compute(
                period: period, containing: day, data: try index.summaryInput(from: first, to: bounds.upperBound))
            let expected = try #require(fixture["expected"] as? [String: Any])
            #expect(
                try canonical(snapshot(summary)) == canonical(expected),
                Comment(rawValue: fixture["id"] as? String ?? ""))
        }
    }
    @Test func calendarBoundsUseMondayAndCrossMonthYearAndLeapDay() throws {
        let week = SummaryPeriod.week.bounds(containing: CalendarDate("2027-01-01")!)
        #expect(week.lowerBound == CalendarDate("2026-12-28") && week.upperBound == CalendarDate("2027-01-03"))
        #expect(
            SummaryPeriod.week.bounds(containing: CalendarDate("2026-09-20")!).lowerBound == CalendarDate("2026-09-14"))
        #expect(
            SummaryPeriod.week.bounds(containing: CalendarDate("2026-09-21")!).lowerBound == CalendarDate("2026-09-21"))
        #expect(
            SummaryPeriod.month.bounds(containing: CalendarDate("2024-02-29")!).upperBound == CalendarDate("2024-02-29")
        )
        #expect(
            SummaryPeriod.month.previous(containing: CalendarDate("2024-03-01")!)?.lowerBound
                == CalendarDate("2024-02-01"))
        #expect(
            SummaryPeriod.month.next(containing: CalendarDate("2026-12-31")!)?.lowerBound == CalendarDate("2027-01-01"))
        #expect(SummaryPeriod.month.previous(containing: CalendarDate("0100-01-01")!) == nil)
        #expect(SummaryPeriod.month.next(containing: CalendarDate("9999-12-31")!) == nil)
    }
    @Test func taskInventoryUsesEndDateAndFutureCompletionInsteadOfCurrentDoneStatus() {
        let before = CalendarDate("2026-09-10")!
        let data = SummaryInput(tasks: [
            .init(created: before, status: .done, due: before, done: CalendarDate("2026-09-22")),
            .init(created: before, status: .done, due: before, done: CalendarDate("2026-09-18")),
            .init(created: before, status: .done, due: before, done: nil),
            .init(created: before, status: .cancelled, due: before, done: nil),
            .init(created: CalendarDate("2026-09-21"), status: .todo, due: before, done: nil),
            .init(created: before, status: .unknown, due: nil, done: nil),
            .init(created: before, status: .todo, due: CalendarDate("2026-09-20"), done: nil),
            .init(created: nil, status: .todo, due: before, done: nil),
        ])
        let summary = PeriodSummary.compute(period: .week, containing: CalendarDate("2026-09-20")!, data: data)
        #expect(summary.counts.createdTasks == 0 && summary.counts.completedTasks == 1)
        #expect(summary.counts.overdueTasks == 1 && summary.counts.undatedTasks == 1)
        #expect(summary.previous.overdueTasks == 2)
    }
    @Test func goalAggregationKeepsHistoryForStreakAndAnnualProgress() throws {
        let weekly = try #require(
            GoalDefinition(id: "sport", key: "sport", name: "Spor", period: .week, kind: .boolean))
        let yearly = try #require(
            GoalDefinition(id: "book", key: "book", name: "Kitap", period: .year, kind: .number, target: 10))
        let milestone = try #require(
            GoalDefinition(id: "water", key: "water", name: "Su", period: .year, kind: .milestone))
        let summary = PeriodSummary.compute(
            period: .week, containing: CalendarDate("2026-09-20")!,
            data: SummaryInput(goals: [
                .init(
                    definition: weekly,
                    logs: [
                        .init(day: CalendarDate("2026-09-07")!, value: .boolean(true)),
                        .init(day: CalendarDate("2026-09-14")!, value: .boolean(true)),
                    ]),
                .init(
                    definition: yearly,
                    logs: [
                        .init(day: CalendarDate("2026-01-01")!, value: .number(2)),
                        .init(day: CalendarDate("2026-09-15")!, value: .number(3)),
                        .init(day: CalendarDate("2026-09-21")!, value: .number(9)),
                    ]),
                .init(
                    definition: milestone,
                    logs: [
                        .init(day: CalendarDate("2026-09-16")!, value: .boolean(true)),
                        .init(day: CalendarDate("2026-09-17")!, value: .boolean(true)),
                    ]),
            ]))
        #expect(summary.goals.first { $0.definition.id == "sport" }?.streak == 2)
        #expect(summary.goals.first { $0.definition.id == "book" }?.progress.done == 5)
        #expect(summary.goals.first { $0.definition.id == "book" }?.contribution == 3)
        #expect(summary.goals.first { $0.definition.id == "book" }?.change == 3)
        #expect(summary.goals.first { $0.definition.id == "water" }?.progress.done == 1)
        #expect(summary.goals.first { $0.definition.id == "water" }?.contribution == 1)
        #expect(summary.goals.first { $0.definition.id == "water" }?.completionDate == CalendarDate("2026-09-16"))
    }
    @Test func annualDifferencesComparePeriodContributionsAcrossYearBoundary() throws {
        let yearly = try #require(
            GoalDefinition(id: "book", key: "book", name: "Kitap", period: .year, kind: .number, target: 10))
        let milestone = try #require(
            GoalDefinition(id: "water", key: "water", name: "Su", period: .year, kind: .milestone))
        let summary = PeriodSummary.compute(
            period: .month, containing: CalendarDate("2027-01-01")!,
            data: SummaryInput(goals: [
                .init(
                    definition: yearly,
                    logs: [
                        .init(day: CalendarDate("2026-11-01")!, value: .number(2)),
                        .init(day: CalendarDate("2026-12-15")!, value: .number(4)),
                        .init(day: CalendarDate("2027-01-15")!, value: .number(3)),
                    ]),
                .init(
                    definition: milestone,
                    logs: [
                        .init(day: CalendarDate("2026-11-01")!, value: .boolean(true)),
                        .init(day: CalendarDate("2026-12-15")!, value: .boolean(true)),
                    ]),
            ]))
        #expect(summary.goals.first { $0.definition.id == "book" }?.progress.done == 3)
        #expect(summary.goals.first { $0.definition.id == "book" }?.change == -1)
        #expect(summary.goals.first { $0.definition.id == "water" }?.change == 0)
    }
    @Test func leaderLimitIsDeterministicAndUnknownLinksDoNotAffectTotals() {
        let day = CalendarDate("2026-09-14")!
        let names = ["Deniz", "Selin", "Baran", "Ece", "Mert", "Deniz Arıkan"]
        let entities = names.map { SummaryInput.Entity(id: $0, name: $0, kind: .person, firstMention: day) }
        let summary = PeriodSummary.compute(
            period: .week, containing: day,
            data: SummaryInput(
                entities: entities,
                mentions: names.map { .init(day: day, entity: $0) } + [.init(day: day, entity: "unknown")]))
        #expect(summary.people.count == 5 && summary.counts.peopleMentions == 6)
        #expect(summary.people.map(\.name) == ["Baran", "Deniz", "Deniz Arıkan", "Ece", "Mert"])
        #expect(summary.counts.firstPeople == 6)
    }
    @Test func queryKeepsOlderGoalAndMentionHistoryButBoundsActivityAndExcludesFrontmatterLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["journal", "people", "goals"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try "---\ntype: person\nname: Deniz Arıkan\n---\n".write(
            to: root.appendingPathComponent("people/Deniz Arıkan.md"), atomically: true, encoding: .utf8)
        try "---\ntype: goal\nname: Spor\nkey: spor\nperiod: week\nkind: boolean\ntarget: 1\n---\n".write(
            to: root.appendingPathComponent("goals/Spor.md"), atomically: true, encoding: .utf8)
        try "---\ngoals:\n  spor: true\n---\n## Events\n- [[Deniz Arıkan]]\n".write(
            to: root.appendingPathComponent("journal/2026-09-07.md"), atomically: true, encoding: .utf8)
        let file = root.appendingPathComponent("journal/2026-09-14.md")
        try
            "---\nvisitor: '[[Deniz Arıkan]]'\ngoals:\n  spor: true\n---\n## Journal\n[[Deniz Arıkan]] and [[Deniz Arıkan|Deniz]]\n"
            .write(to: file, atomically: true, encoding: .utf8)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let first = CalendarDate("2026-09-14")!
        let last = CalendarDate("2026-09-20")!
        let input = try index.summaryInput(from: first, to: last)
        #expect(input.days.count == 1 && input.mentions.count == 2)
        #expect(input.entities.first?.firstMention == CalendarDate("2026-09-07"))
        let summary = PeriodSummary.compute(period: .week, containing: first, data: input)
        #expect(summary.counts.firstPeople == 0 && summary.counts.peopleMentions == 2)
        #expect(summary.counts.events == 0 && summary.counts.writtenDays == 1)
        #expect(summary.goals.first?.streak == 2)
        let original = try canonical(snapshot(summary))
        try "\nMore writing\n".append(to: file)
        try index.refresh(vaultRoot: root)
        let incremental = PeriodSummary.compute(
            period: .week, containing: first, data: try index.summaryInput(from: first, to: last))
        try index.rebuild(vaultRoot: root)
        let rebuilt = PeriodSummary.compute(
            period: .week, containing: first, data: try index.summaryInput(from: first, to: last))
        #expect(try canonical(snapshot(incremental)) == canonical(snapshot(rebuilt)))
        #expect(try canonical(snapshot(rebuilt)) == original)
        #expect(try index.summaryInput(from: last, to: first).days.isEmpty)
    }
    @Test func emptyPeriodCanStillHaveOpenInventory() {
        let day = CalendarDate("2026-09-14")!
        let summary = PeriodSummary.compute(
            period: .week, containing: day,
            data: SummaryInput(tasks: [
                .init(created: day.addingDays(-20), status: .todo, due: day.addingDays(-1), done: nil)
            ]))
        #expect(summary.isEmpty && summary.counts.overdueTasks == 1)
    }
}

extension String {
    fileprivate func append(to file: URL) throws {
        let source = try String(contentsOf: file, encoding: .utf8)
        try (source + self).write(to: file, atomically: true, encoding: .utf8)
    }
}
