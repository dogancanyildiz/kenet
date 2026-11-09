import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

struct TodayPageCopyTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        value.firstWeekday = 2  // Monday
        return value
    }

    @Test func greetingBands() {
        #expect(TodayGreeting.resolve(hour: 5) == .morning)
        #expect(TodayGreeting.resolve(hour: 11) == .morning)
        #expect(TodayGreeting.resolve(hour: 12) == .afternoon)
        #expect(TodayGreeting.resolve(hour: 17) == .afternoon)
        #expect(TodayGreeting.resolve(hour: 18) == .evening)
        #expect(TodayGreeting.resolve(hour: 4) == .evening)
        #expect(TodayGreeting.resolve(hour: 0) == .evening)
    }

    @Test(arguments: ["tr_TR", "en_US"])
    func summaryOmitsZeroPartsAndEmptyPage(_ language: String) {
        let locale = Locale(identifier: language)
        let empty = TodaySummaryCopy.parts(
            greeting: .morning, events: 0, tasks: 0, goals: 0, locale: locale)
        #expect(empty.contains { if case .text(let t) = $0 { return t.contains("boş") || t.contains("empty") }; return false })

        let full = TodaySummaryCopy.parts(
            greeting: .afternoon, events: 2, tasks: 6, goals: 3, locale: locale)
        let counts = full.compactMap { part -> (Int, String)? in
            if case .count(let value, let noun, _) = part { return (value, noun) }
            return nil
        }
        #expect(counts.map(\.0) == [2, 6, 3])
        #expect(counts.allSatisfy { !$0.1.isEmpty })

        let eventsOnly = TodaySummaryCopy.parts(
            greeting: nil, events: 1, tasks: 0, goals: 0, locale: locale)
        #expect(eventsOnly.compactMap { if case .count(let v, _, _) = $0 { return v }; return nil } == [1])
    }

    @Test func insightChipsHideZeros() {
        let day = CalendarDate("2026-09-20")!
        let hidden = TodayInsightChip.make(
            from: .init(
                longestDailyStreak: 0, streakGoalID: nil, yesterdayEventCount: 0, yesterday: day,
                lastPersonName: nil, lastPersonID: nil))
        #expect(hidden.isEmpty)

        let shown = TodayInsightChip.make(
            from: .init(
                longestDailyStreak: 12, streakGoalID: "g1", yesterdayEventCount: 4, yesterday: day,
                lastPersonName: "Baran", lastPersonID: "people/baran.md"))
        #expect(shown.count == 3)
        #expect(shown[0] == .streak(days: 12, goalID: "g1"))
        #expect(shown[1] == .yesterdayEvents(count: 4, day: day))
        #expect(shown[2] == .lastMeeting(name: "Baran", entityID: "people/baran.md"))
    }

    @Test func weekStripMondayStartAndYearBoundary() {
        // 2026-01-01 is Thursday; week starting Monday is 2025-12-29 ... 2026-01-04.
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let days = TodayWeekStripMath.daysInWeek(containing: day, calendar: calendar)
        #expect(days.count == 7)
        #expect(calendar.component(.year, from: days[0]) == 2025)
        #expect(calendar.component(.month, from: days[0]) == 12)
        #expect(calendar.component(.day, from: days[0]) == 29)
        #expect(calendar.component(.year, from: days[6]) == 2026)
        #expect(calendar.component(.day, from: days[6]) == 4)
        #expect(calendar.component(.weekday, from: days[0]) == 2)

        let today = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let future = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2))!
        #expect(TodayWeekStripMath.isSelectable(today, today: today, calendar: calendar))
        #expect(!TodayWeekStripMath.isSelectable(future, today: today, calendar: calendar))
    }

    @Test func aboveFoldBudgetFoldsTasksWhenCrowded() {
        #expect(
            !TodayAboveFoldBudget.shouldFoldTasks(goalCount: 0, openTaskCount: 2, eventCount: 1))
        #expect(
            TodayAboveFoldBudget.shouldFoldTasks(goalCount: 3, openTaskCount: 8, eventCount: 2))
        #expect(
            TodayAboveFoldBudget.aboveFoldSections(
                hasGoals: true, hasTasks: true, hasEvents: true)
                == ["masthead", "week", "summary", "chips", "goals", "tasks", "events"])
    }

    @Test func dayRingProgress() {
        #expect(TodayDayRing.progress(completed: 2, total: 3) == 2.0 / 3.0)
        #expect(TodayDayRing.remaining(completed: 2, total: 3) == 1)
        #expect(!TodayDayRing.showsRing(total: 0))
        #expect(TodayDayRing.showsRing(total: 1))
    }

    @Test func longestDailyStreakPicksMax() {
        let goals = [
            GoalDefinition(id: "a", key: "a", name: "A", period: .day, kind: .boolean)!,
            GoalDefinition(id: "b", key: "b", name: "B", period: .day, kind: .boolean)!,
            GoalDefinition(id: "c", key: "c", name: "C", period: .week, kind: .boolean)!,
        ]
        let statuses: [String: GoalStatus] = [
            "a": GoalStatus(
                periodStart: CalendarDate("2026-09-20")!, periodEnd: CalendarDate("2026-09-20")!,
                progress: GoalAmount(done: 1, target: 1), streak: 3, longestStreak: 3,
                isPendingToday: false, score: 100, yearDone: 3, yearProgress: nil),
            "b": GoalStatus(
                periodStart: CalendarDate("2026-09-20")!, periodEnd: CalendarDate("2026-09-20")!,
                progress: GoalAmount(done: 1, target: 1), streak: 12, longestStreak: 12,
                isPendingToday: false, score: 100, yearDone: 12, yearProgress: nil),
            "c": GoalStatus(
                periodStart: CalendarDate("2026-09-15")!, periodEnd: CalendarDate("2026-09-21")!,
                progress: GoalAmount(done: 1, target: 1), streak: 99, longestStreak: 99,
                isPendingToday: false, score: nil, yearDone: 1, yearProgress: nil),
        ]
        let result = TodayInsightChip.longestDailyStreak(goals: goals, statuses: statuses)
        #expect(result.days == 12)
        #expect(result.goalID == "b")
    }

    @Test func lastPersonWithinWindow() {
        let today = CalendarDate("2026-09-20")!
        let people = [
            EntitySummary(
                id: "people/old.md", kind: "person", name: "Eski", qualifier: nil, aliases: [],
                incomingLinks: 0),
            EntitySummary(
                id: "people/baran.md", kind: "person", name: "Baran", qualifier: nil, aliases: [],
                incomingLinks: 0),
            EntitySummary(
                id: "places/cafe.md", kind: "place", name: "Kafe", qualifier: nil, aliases: [],
                incomingLinks: 0),
        ]
        let encounters: [String: CalendarDate] = [
            "people/old.md": CalendarDate("2026-09-01")!,
            "people/baran.md": CalendarDate("2026-09-18")!,
            "places/cafe.md": CalendarDate("2026-09-19")!,
        ]
        let person = TodayInsightChip.lastPerson(
            people: people, encounters: encounters, today: today, windowDays: 7)
        #expect(person?.id == "people/baran.md")
        #expect(person?.name == "Baran")
    }
}
