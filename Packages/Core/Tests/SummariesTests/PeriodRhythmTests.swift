import Foundation
import GoalTracking
import Summaries
import Testing
import VaultFormat
import VaultIndex

struct PeriodRhythmTests {
    @Test func rhythmFixturesMatchHandCountedExpectations() throws {
        let fixtures = fixtureDirectory()
        let cases = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtures.appendingPathComponent("summaries/period-rhythm.json")))
                as? [[String: Any]])
        #expect(cases.count == 4)
        for fixture in cases {
            let vault = try #require(fixture["vault"] as? String)
            let period = try #require((fixture["period"] as? String).flatMap(SummaryPeriod.init(rawValue:)))
            let day = try #require((fixture["containing"] as? String).flatMap { CalendarDate($0) })
            let today = (fixture["today"] as? String).flatMap { CalendarDate($0) }
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: fixtures.appendingPathComponent("vaults/" + vault))
            let bounds = period.bounds(containing: day)
            let first = period.previous(containing: day)?.lowerBound ?? bounds.lowerBound
            let summary = PeriodSummary.compute(
                period: period, containing: day, data: try index.summaryInput(from: first, to: bounds.upperBound),
                today: today)
            let expected = try #require(fixture["expected"] as? [String: Any])
            #expect(
                try canonical(rhythmSnapshot(summary)) == canonical(expected),
                Comment(rawValue: fixture["id"] as? String ?? ""))
        }
    }

    @Test func unitsAreDaysMonthSlicesFromTheFirstAndMonths() throws {
        func spans(_ period: SummaryPeriod, _ day: String) -> [String] {
            period.units(containing: CalendarDate(day)!).map { "\($0.lowerBound.day)-\($0.upperBound.day)" }
        }
        #expect(spans(.month, "2026-10-07") == ["1-7", "8-14", "15-21", "22-28", "29-31"])
        #expect(spans(.month, "2026-02-10") == ["1-7", "8-14", "15-21", "22-28"])
        #expect(spans(.month, "2024-02-10") == ["1-7", "8-14", "15-21", "22-28", "29-29"])
        #expect(spans(.month, "2026-04-30") == ["1-7", "8-14", "15-21", "22-28", "29-30"])
        #expect(SummaryPeriod.week.units(containing: CalendarDate("2027-01-01")!).count == 7)
        #expect(
            SummaryPeriod.week.units(containing: CalendarDate("2027-01-01")!).first?.lowerBound
                == CalendarDate("2026-12-28"))
        let months = SummaryPeriod.year.units(containing: CalendarDate("2024-07-01")!)
        #expect(months.count == 12 && months[1].upperBound == CalendarDate("2024-02-29"))
        #expect(months.last?.upperBound == CalendarDate("2024-12-31"))
    }

    @Test func yearBoundsFollowTheCalendarYear() {
        let year = SummaryPeriod.year.bounds(containing: CalendarDate("2026-10-07")!)
        #expect(year.lowerBound == CalendarDate("2026-01-01") && year.upperBound == CalendarDate("2026-12-31"))
        #expect(
            SummaryPeriod.year.previous(containing: CalendarDate("2026-01-01")!)?.upperBound
                == CalendarDate("2025-12-31"))
        #expect(
            SummaryPeriod.year.next(containing: CalendarDate("2026-12-31")!)?.lowerBound
                == CalendarDate("2027-01-01"))
        #expect(SummaryPeriod.year.previous(containing: CalendarDate("0100-06-01")!) == nil)
        #expect(SummaryPeriod.year.next(containing: CalendarDate("9999-06-01")!) == nil)
    }

    @Test func sameDateClampsToTheShorterMonth() {
        #expect(SummaryPeriod.week.sameDate(before: CalendarDate("2026-10-07")!) == CalendarDate("2026-09-30"))
        #expect(SummaryPeriod.month.sameDate(before: CalendarDate("2026-03-31")!) == CalendarDate("2026-02-28"))
        #expect(SummaryPeriod.year.sameDate(before: CalendarDate("2028-02-29")!) == CalendarDate("2027-02-28"))
    }

    @Test func runningPeriodComparesToTheSameDateAndItsLastDayToTheWholePeriod() {
        let data = SummaryInput(
            days: (1...31).map {
                .init(date: CalendarDate(year: 2026, month: 3, day: $0)!, events: 1, hasJournal: false)
            }
                + (1...30).map {
                    .init(date: CalendarDate(year: 2026, month: 4, day: $0)!, events: 2, hasJournal: false)
                })
        let running = PeriodSummary.compute(
            period: .month, containing: CalendarDate("2026-04-10")!, data: data, today: CalendarDate("2026-04-10"))
        #expect(running.isRunning && running.counts.events == 20 && running.previous.events == 10)
        #expect(running.previousMeasuredRange?.upperBound == CalendarDate("2026-03-10"))
        // The last day of April has nothing still to come: the whole of March, 31 days, is compared.
        let last = PeriodSummary.compute(
            period: .month, containing: CalendarDate("2026-04-30")!, data: data, today: CalendarDate("2026-04-30"))
        #expect(!last.isRunning && last.previous.events == 31 && last.counts.events == 60)
        // A period that has not started yet is counted whole.
        let coming = PeriodSummary.compute(
            period: .month, containing: CalendarDate("2026-04-10")!, data: data, today: CalendarDate("2026-03-20"))
        #expect(!coming.isRunning && coming.counts.events == 60 && coming.previous.events == 31)
        #expect(running.units.reduce(0) { $0 + $1.events } == running.counts.events)
        #expect(running.units.map(\.measuredDays) == [7, 3, 0, 0, 0])
        #expect(running.previousUnits.map(\.events) == [7, 7, 7, 7, 3])
    }

    @Test func longerUnitIsWrittenWhenHalfItsMeasuredDaysAre() {
        let range = CalendarDate("2026-10-01")!...CalendarDate("2026-10-07")!
        #expect(SummaryUnit(range: range, events: 0, writtenDays: 3, measuredDays: 7).writing == .partial)
        #expect(SummaryUnit(range: range, events: 0, writtenDays: 4, measuredDays: 7).writing == .full)
        #expect(SummaryUnit(range: range, events: 0, writtenDays: 3, measuredDays: 6).writing == .full)
        #expect(SummaryUnit(range: range, events: 5, writtenDays: 0, measuredDays: 7).writing == .none)
        #expect(SummaryUnit(range: range, events: 0, writtenDays: 0, measuredDays: 0).writing == .notStarted)
    }

    @Test func firstMentionsListEveryNameOfTheRangeByDayThenName() {
        let day = CalendarDate("2026-10-06")!
        let entities =
            (["Zeren", "Arda", "Bilge", "Cem", "Dora", "Ekin"].map {
                SummaryInput.Entity(id: "people/\($0).md", name: $0, kind: .person, firstMention: day)
            }) + [
                .init(id: "people/Ufuk.md", name: "Ufuk", kind: .person, firstMention: CalendarDate("2026-10-05")),
                .init(id: "people/Eski.md", name: "Eski", kind: .person, firstMention: CalendarDate("2026-10-04")),
                .init(id: "places/Kıyı.md", name: "Kıyı", kind: .place, firstMention: day),
            ]
        let summary = PeriodSummary.compute(
            period: .week, containing: day, data: SummaryInput(entities: entities))
        #expect(summary.firstPeople.map(\.name) == ["Ufuk", "Arda", "Bilge", "Cem", "Dora", "Ekin", "Zeren"])
        #expect(summary.firstPeople.count == summary.counts.firstPeople)
        #expect(summary.firstPlaces.map(\.id) == ["places/Kıyı.md"])
    }

    @Test func yearTargetsCountTheYearsDaysAndMondayWeeks() throws {
        let weekly = try #require(
            GoalDefinition(id: "swim", key: "swim", name: "Yüzme", period: .week, kind: .boolean, target: 2))
        let daily = try #require(
            GoalDefinition(id: "walk", key: "walk", name: "Yürüyüş", period: .day, kind: .boolean))
        let logs = [GoalLog(day: CalendarDate("2026-01-01")!, value: .boolean(true))]
        let summary = PeriodSummary.compute(
            period: .year, containing: CalendarDate("2026-06-01")!,
            data: SummaryInput(goals: [.init(definition: weekly, logs: logs), .init(definition: daily, logs: logs)]))
        // 2026 touches 53 Monday weeks: 29 December 2025 to 28 December 2026.
        #expect(summary.goals.first { $0.definition.id == "swim" }?.progress.target == 106)
        #expect(summary.goals.first { $0.definition.id == "walk" }?.progress.target == 365)
        #expect(summary.goals.allSatisfy { $0.progress.done == 1 })
    }

    @Test func dailyGoalCarriesHeatmapMarksOfTheMeasuredDaysOnly() throws {
        let daily = try #require(GoalDefinition(id: "walk", key: "walk", name: "Yürüyüş", period: .day, kind: .boolean))
        let weekly = try #require(
            GoalDefinition(id: "swim", key: "swim", name: "Yüzme", period: .week, kind: .boolean, target: 2))
        let logs = [GoalLog(day: CalendarDate("2026-10-05")!, value: .boolean(true))]
        let today = CalendarDate("2026-10-07")!
        let summary = PeriodSummary.compute(
            period: .week, containing: today,
            data: SummaryInput(goals: [.init(definition: daily, logs: logs), .init(definition: weekly, logs: logs)]),
            today: today)
        let marks = try #require(summary.goals.first { $0.definition.id == "walk" }).dayMarks
        #expect(marks.keys.sorted() == ["2026-10-05", "2026-10-06", "2026-10-07"].compactMap { CalendarDate($0) })
        #expect(marks[CalendarDate("2026-10-05")!] == .full)
        #expect(try #require(summary.goals.first { $0.definition.id == "swim" }).dayMarks.isEmpty)
    }

    @Test func goalChangeComparesTheMeasuredDaysAndStreakChangeThePeriodEnds() throws {
        let book = try #require(
            GoalDefinition(id: "book", key: "book", name: "Kitap", period: .day, kind: .number, target: 20))
        let logs = [
            GoalLog(day: CalendarDate("2026-09-28")!, value: .number(10)),
            GoalLog(day: CalendarDate("2026-10-01")!, value: .number(30)),
            GoalLog(day: CalendarDate("2026-10-05")!, value: .number(20)),
            GoalLog(day: CalendarDate("2026-10-06")!, value: .number(20)),
        ]
        let today = CalendarDate("2026-10-07")!
        let data = SummaryInput(goals: [.init(definition: book, logs: logs)])
        let running = try #require(
            PeriodSummary.compute(period: .week, containing: today, data: data, today: today).goals.first)
        // Monday to Wednesday: 40 against 10 on Monday to Wednesday of the week before, not against its 40.
        #expect(running.contribution == 40 && running.change == 30)
        // Today's chain is 5 and 6 October; the week before ended on a miss.
        #expect(running.streak == 2 && running.streakChange == 2)
        let ended = try #require(
            PeriodSummary.compute(period: .week, containing: CalendarDate("2026-10-11")!, data: data).goals.first)
        #expect(ended.change == 0 && ended.streakChange == 0)
    }

    @Test func leapDayYearComparesSixtyDaysWithSixtyOne() {
        let days = (0..<800).compactMap { CalendarDate("2027-06-01")!.addingDays($0) }.map {
            SummaryInput.Day(date: $0, events: 1, hasJournal: false)
        }
        let today = CalendarDate("2029-03-01")!
        let summary = PeriodSummary.compute(
            period: .year, containing: today, data: SummaryInput(days: days), today: today)
        #expect(summary.measuredRange == CalendarDate("2029-01-01")!...today)
        #expect(summary.previousMeasuredRange == CalendarDate("2028-01-01")!...CalendarDate("2028-03-01")!)
        #expect(summary.counts.events == 60 && summary.previous.events == 61)
        #expect(SummaryPeriod.year.sameDate(before: CalendarDate("2028-02-29")!) == CalendarDate("2027-02-28"))
    }

    /// The summary groups logs by day; the reference reads every day of the range one by one.
    @Test func goalProgressMatchesTheDayByDayReference() throws {
        let definitions = [
            try #require(GoalDefinition(id: "a", key: "a", name: "A", period: .day, kind: .number, target: 7)),
            try #require(GoalDefinition(id: "b", key: "b", name: "B", period: .week, kind: .boolean, target: 3)),
            try #require(GoalDefinition(id: "c", key: "c", name: "C", period: .year, kind: .number, target: 12)),
            try #require(GoalDefinition(id: "d", key: "d", name: "D", period: .day, kind: .boolean)),
        ]
        let first = CalendarDate("2025-11-20")!
        var state: UInt64 = 11
        func roll(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % limit
        }
        let goals = definitions.map { definition in
            SummaryInput.Goal(
                definition: definition,
                logs: (0..<500).compactMap { offset -> GoalLog? in
                    guard roll(3) == 0, let day = first.addingDays(offset) else { return nil }
                    return definition.kind == .boolean
                        ? GoalLog(day: day, value: .boolean(roll(4) != 0))
                        : GoalLog(day: day, value: .number(Double(roll(9)) + 0.25))
                })
        }
        let data = SummaryInput(goals: goals)
        func reference(_ goal: SummaryInput.Goal, _ range: ClosedRange<CalendarDate>) -> (Double, Double?) {
            var sum = 0.0
            var days = 0
            var weeks: Set<CalendarDate> = []
            var cursor: CalendarDate? = range.lowerBound
            while let day = cursor, day <= range.upperBound {
                days += 1
                weeks.insert(day.startOfWeek ?? day)
                sum +=
                    GoalProgress.compute(
                        definition: goal.definition, logs: goal.logs.filter { $0.day == day }, today: day
                    ).progress.done
                cursor = day.addingDays(1)
            }
            switch goal.definition.period {
            case .day: return (sum, goal.definition.target * Double(days))
            case .week: return (sum, goal.definition.target * Double(weeks.count))
            case .year: return (sum, nil)
            }
        }
        for period in SummaryPeriod.allCases {
            for offset in stride(from: 0, to: 500, by: 37) {
                let day = first.addingDays(offset)!
                let summary = PeriodSummary.compute(period: period, containing: day, data: data, today: day)
                for goal in goals {
                    let shown = try #require(summary.goals.first { $0.definition.id == goal.definition.id })
                    // Done ends at today like the counts; the target is the whole period's.
                    let measured = reference(goal, summary.measuredRange).0
                    #expect(shown.contribution == measured)
                    if let target = reference(goal, summary.range).1 {
                        #expect(shown.progress.target == target && shown.progress.done == measured)
                    }
                    let before = summary.previousMeasuredRange.map { reference(goal, $0).0 } ?? 0
                    #expect(shown.change == measured - before)
                }
            }
        }
    }
}
