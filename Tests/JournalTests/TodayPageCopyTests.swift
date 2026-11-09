import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

struct TodayPageCopyTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        value.firstWeekday = firstWeekday
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
        #expect(TodayGreeting.resolve(hour: 23) == .evening)
    }

    @Test func greetingAtMidnightAndEndOfDayUsesCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 0))!
        let almost = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 20, hour: 23, minute: 59))!
        #expect(TodayGreeting.resolve(date: midnight, calendar: calendar) == .evening)
        #expect(TodayGreeting.resolve(date: almost, calendar: calendar) == .evening)
    }

    @Test func emptySummaryIsGreetingOnly() {
        let tr = Locale(identifier: "tr_TR")
        let en = Locale(identifier: "en_US")
        let trParts = TodaySummaryCopy.parts(
            greeting: .morning, events: 0, tasks: 0, goals: 0, locale: tr)
        let enParts = TodaySummaryCopy.parts(
            greeting: .evening, events: 0, tasks: 0, goals: 0, locale: en)
        #expect(TodaySummaryCopy.spoken(trParts) == "Günaydın.")
        #expect(TodaySummaryCopy.spoken(enParts) == "Good evening.")
        #expect(trParts.first == .text("Günaydın."))
        #expect(
            TodaySummaryCopy.parts(greeting: nil, events: 0, tasks: 0, goals: 0, locale: tr).isEmpty)
    }

    @Test func summaryFullSentenceEqualityTurkish() {
        let locale = Locale(identifier: "tr_TR")
        let three = TodaySummaryCopy.parts(
            greeting: .morning, events: 2, tasks: 6, goals: 3, locale: locale)
        #expect(
            TodaySummaryCopy.spoken(three)
                == "Günaydın. Bugün 2 olay, 6 görev ve 3 hedef var.")
        #expect(
            {
                if case .text(let first) = three.first { return first == "Günaydın." }
                return false
            }())

        let two = TodaySummaryCopy.parts(
            greeting: nil, events: 2, tasks: 0, goals: 1, locale: locale)
        #expect(TodaySummaryCopy.spoken(two) == "Bugün 2 olay ve 1 hedef var.")

        let one = TodaySummaryCopy.parts(
            greeting: nil, events: 0, tasks: 4, goals: 0, locale: locale)
        #expect(TodaySummaryCopy.spoken(one) == "Bugün 4 görev var.")
    }

    @Test func summaryFullSentenceEqualityEnglish() {
        let locale = Locale(identifier: "en_US")
        let three = TodaySummaryCopy.parts(
            greeting: .morning, events: 2, tasks: 6, goals: 3, locale: locale)
        #expect(
            TodaySummaryCopy.spoken(three)
                == "Good morning. Today you have 2 events, 6 tasks and 3 goals.")

        let two = TodaySummaryCopy.parts(
            greeting: nil, events: 1, tasks: 1, goals: 0, locale: locale)
        #expect(TodaySummaryCopy.spoken(two) == "Today you have 1 event and 1 task.")

        let one = TodaySummaryCopy.parts(
            greeting: nil, events: 0, tasks: 0, goals: 2, locale: locale)
        #expect(TodaySummaryCopy.spoken(one) == "Today you have 2 goals.")
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
        #expect(shown[0].title(locale: Locale(identifier: "tr_TR")).contains("zincir"))
    }

    @Test func weekStripMondayStartAndYearBoundary() {
        let calendar = calendar(firstWeekday: 2)
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let days = TodayWeekStripMath.daysInWeek(containing: day, calendar: calendar)
        #expect(days.count == 7)
        #expect(calendar.component(.year, from: days[0]) == 2025)
        #expect(calendar.component(.month, from: days[0]) == 12)
        #expect(calendar.component(.day, from: days[0]) == 29)
        #expect(calendar.component(.weekday, from: days[0]) == 2)
    }

    @Test func weekStripSundayStart() {
        let calendar = calendar(firstWeekday: 1)
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!  // Thursday
        let days = TodayWeekStripMath.daysInWeek(containing: day, calendar: calendar)
        #expect(calendar.component(.weekday, from: days[0]) == 1)
        #expect(calendar.component(.day, from: days[0]) == 28)  // 2025-12-28 Sunday
        #expect(calendar.component(.year, from: days[0]) == 2025)
    }

    @Test func weekStripSelectability() {
        let calendar = calendar(firstWeekday: 2)
        let today = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 15))!
        let future = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2))!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0))!
        #expect(TodayWeekStripMath.isSelectable(today, today: today, calendar: calendar))
        #expect(TodayWeekStripMath.isSelectable(midnight, today: today, calendar: calendar))
        #expect(!TodayWeekStripMath.isSelectable(future, today: today, calendar: calendar))
    }

    @Test func aboveFoldBudgetRequiresTwoHiddenAndCalendar() {
        #expect(
            !TodayAboveFoldBudget.shouldFoldTasks(
                goalCount: 3, openTaskCount: 4, eventCount: 1, viewportHeight: 844))
        #expect(
            TodayAboveFoldBudget.shouldFoldTasks(
                goalCount: 3, openTaskCount: 5, eventCount: 1, viewportHeight: 844))
        #expect(
            !TodayAboveFoldBudget.shouldFoldTasks(
                goalCount: 3, openTaskCount: 8, eventCount: 1, viewportHeight: 844,
                foldsAllowed: false))
        #expect(
            TodayAboveFoldBudget.shouldFoldTasks(
                goalCount: 0, openTaskCount: 5, eventCount: 1, calendarEventCount: 3,
                viewportHeight: 600))
    }

    @Test func dayRingProgressAndLabel() {
        #expect(TodayDayRing.progress(completed: 2, total: 3) == 2.0 / 3.0)
        #expect(TodayDayRing.remaining(completed: 2, total: 3) == 1)
        #expect(!TodayDayRing.showsRing(total: 0))
        let label = TodayDayRing.accessibilityLabel(remaining: 3, locale: Locale(identifier: "tr_TR"))
        #expect(label.contains("3"))
        #expect(label.contains("hedef"))
    }

    @Test func longestDailyStreakPicksMax() {
        let goals = [
            GoalDefinition(id: "a", key: "a", name: "A", period: .day, kind: .boolean)!,
            GoalDefinition(id: "b", key: "b", name: "B", period: .day, kind: .boolean)!,
        ]
        let day = CalendarDate("2026-09-20")!
        let statuses: [String: GoalStatus] = [
            "a": GoalStatus(
                periodStart: day, periodEnd: day, progress: GoalAmount(done: 1, target: 1),
                streak: 3, longestStreak: 3, isPendingToday: false, score: 100, yearDone: 3,
                yearProgress: nil),
            "b": GoalStatus(
                periodStart: day, periodEnd: day, progress: GoalAmount(done: 1, target: 1),
                streak: 12, longestStreak: 12, isPendingToday: false, score: 100, yearDone: 12,
                yearProgress: nil),
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
        ]
        let encounters: [String: CalendarDate] = [
            "people/old.md": CalendarDate("2026-09-01")!,
            "people/baran.md": CalendarDate("2026-09-18")!,
        ]
        let person = TodayInsightChip.lastPerson(
            people: people, encounters: encounters, today: today, windowDays: 7)
        #expect(person?.name == "Baran")
    }
}
