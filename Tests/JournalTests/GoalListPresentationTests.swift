import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

struct GoalListPresentationTests {
    private let day = CalendarDate("2026-09-20")!
    private let tr = Locale(identifier: "tr")
    private let en = Locale(identifier: "en")

    private func languageBundle(_ code: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func numberGoal(
        period: GoalPeriod = .day, target: Double = 20, unit: String? = "sayfa"
    ) throws -> GoalDefinition {
        try #require(
            GoalDefinition(
                id: "goals/Kitap.md", key: "kitap", name: "Kitap", period: period, kind: .number,
                target: target, unit: unit))
    }

    @Test func percentAndRemainingCopy() throws {
        let turkish = try languageBundle("tr")
        let english = try languageBundle("en")
        let goal = try numberGoal()
        #expect(GoalListPresentation.percent(done: 12, target: 20) == 60)
        #expect(GoalListPresentation.percent(done: 30, target: 20) == 150)
        #expect(GoalListPresentation.percentLabel(done: 12, target: 20) == "%60")

        let open = GoalStatus(
            periodStart: day, periodEnd: day, progress: GoalAmount(done: 12, target: 20),
            streak: 3, longestStreak: 5, isPendingToday: true, score: 87, yearDone: 12,
            yearProgress: nil)
        #expect(
            GoalListPresentation.remainingText(
                goal: goal, status: open, bundle: turkish, locale: tr)
                == "Bugün · 8 sayfa kaldı")
        let pages = try numberGoal(unit: "pages")
        #expect(
            GoalListPresentation.remainingText(
                goal: pages, status: open, bundle: english, locale: en)
                == "Today · 8 pages left")

        let done = GoalStatus(
            periodStart: day, periodEnd: day, progress: GoalAmount(done: 20, target: 20),
            streak: 3, longestStreak: 5, isPendingToday: false, score: 87, yearDone: 20,
            yearProgress: nil)
        #expect(
            GoalListPresentation.remainingText(
                goal: goal, status: done, bundle: turkish, locale: tr) == nil)
    }

    @Test func tallyCellsCoverFilledEmptyForgivenAndToday() throws {
        let goal = try numberGoal()
        // Six past days + today: full, full, miss-forgiven, full, empty, full, today empty.
        let logs: [GoalLog] = [
            GoalLog(day: day.addingDays(-6)!, value: .number(20)),
            GoalLog(day: day.addingDays(-5)!, value: .number(20)),
            // -4 missed, forgiven when -3 succeeds and -6/-5 succeeded
            GoalLog(day: day.addingDays(-3)!, value: .number(20)),
            GoalLog(day: day.addingDays(-2)!, value: .number(20)),
            GoalLog(day: day.addingDays(-1)!, value: .number(20)),
        ]
        let cells = GoalListPresentation.tallyDays(goal: goal, logs: logs, today: day)
        #expect(cells.count == 7)
        #expect(cells.map(\.fill) == [
            .filled, .filled, .forgiven, .filled, .filled, .filled, .empty,
        ])
        #expect(cells.filter(\.isToday).count == 1)
        #expect(cells.last?.isToday == true)
        #expect(cells.last?.fill == .empty)
        #expect(cells[2].heatmapKind == .forgiven)
    }

    @Test func yearlyPaceIsTargetOverTwelve() {
        #expect(GoalListPresentation.yearlyPace(target: 24) == 2)
        #expect(GoalListPresentation.yearlyPace(target: 12) == 1)
        #expect(abs(GoalListPresentation.yearlyPace(target: 10) - (10.0 / 12.0)) < 0.0001)
    }

    @Test func yearMonthBarsMarkFutureMonths() throws {
        let goal = try numberGoal(period: .year, target: 24, unit: "kitap")
        let logs = [
            GoalLog(day: CalendarDate("2026-01-10")!, value: .number(1)),
            GoalLog(day: CalendarDate("2026-02-10")!, value: .number(2)),
            GoalLog(day: CalendarDate("2026-09-10")!, value: .number(1)),
        ]
        let bars = GoalListPresentation.yearMonthBars(goal: goal, logs: logs, today: day)
        #expect(bars.count == 12)
        #expect(bars[0].total == 1 && bars[0].isFuture == false)
        #expect(bars[1].total == 2)
        #expect(bars[8].total == 1)  // September
        #expect(bars[9].isFuture && bars[10].isFuture && bars[11].isFuture)
        #expect(bars[1].fraction == 1)
    }

    @Test func streakAndPeriodChipCopy() throws {
        let turkish = try languageBundle("tr")
        let english = try languageBundle("en")
        #expect(
            GoalListPresentation.streakText(12, bundle: turkish, locale: tr) == "Zincir 12 gün")
        #expect(
            GoalListPresentation.streakText(12, bundle: english, locale: en) == "Streak 12 days")
        #expect(GoalListPresentation.periodChip(.day, bundle: turkish, locale: tr) == "Günlük")
        #expect(GoalListPresentation.periodChip(.week, bundle: english, locale: en) == "Weekly")
        #expect(GoalListPresentation.kindTab(.boolean, bundle: turkish, locale: tr) == "İşaret")
        #expect(GoalListPresentation.kindTab(.boolean, bundle: english, locale: en) == "Mark")
    }

    @Test func completedGoalsSortLast() throws {
        let a = try #require(
            GoalDefinition(
                id: "goals/A.md", key: "a", name: "Açık", period: .day, kind: .boolean, target: 1))
        let b = try #require(
            GoalDefinition(
                id: "goals/B.md", key: "b", name: "Bitti", period: .day, kind: .boolean, target: 1))
        let open = GoalStatus(
            periodStart: day, periodEnd: day, progress: GoalAmount(done: 0, target: 1),
            streak: 0, longestStreak: 0, isPendingToday: true, score: nil, yearDone: 0,
            yearProgress: nil)
        let done = GoalStatus(
            periodStart: day, periodEnd: day, progress: GoalAmount(done: 1, target: 1),
            streak: 1, longestStreak: 1, isPendingToday: false, score: nil, yearDone: 1,
            yearProgress: nil)
        let ordered = GoalListPresentation.ordered([b, a]) { $0.key == "b" ? done : open }
        #expect(ordered.map(\.key) == ["a", "b"])
    }
}
