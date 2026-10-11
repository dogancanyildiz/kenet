import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

struct GoalScoreCopyTests {
    private func languageBundle(_ code: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func scoreSentenceUsesTheSelectedCatalog() throws {
        let turkish = try languageBundle("tr")
        let english = try languageBundle("en")
        let tr = Locale(identifier: "tr")
        let en = Locale(identifier: "en")
        #expect(GoalScoreCopy.sentence(87, bundle: turkish, locale: tr) == "Son 30 gün %87")
        #expect(GoalScoreCopy.sentence(0, bundle: turkish, locale: tr) == "Son 30 gün %0")
        #expect(GoalScoreCopy.sentence(100, bundle: turkish, locale: tr) == "Son 30 gün %100")
        #expect(GoalScoreCopy.sentence(87, bundle: english, locale: en) == "Last 30 days 87%")
        #expect(GoalScoreCopy.sentence(87, bundle: english, locale: en) != "Son 30 gün %87")
    }

    @Test func dailyRowPlacesScoreBesideTheStreakAndWeekOmitsIt() throws {
        let turkish = try languageBundle("tr")
        let english = try languageBundle("en")
        let day = CalendarDate("2026-10-04")!
        let water = try #require(
            GoalDefinition(id: "goals/Su.md", key: "su", name: "Su", period: .day, kind: .number, target: 8))
        let status = GoalStatus(
            periodStart: day, periodEnd: day, progress: GoalAmount(done: 0, target: 8),
            streak: 4, longestStreak: 4, isPendingToday: true, score: 87, yearDone: 0, yearProgress: nil)
        #expect(
            GoalRowPresentation.meta(goal: water, status: status, bundle: turkish, locale: Locale(identifier: "tr"))
                == "Güncel zincir: 4\nSon 30 gün %87")
        #expect(
            GoalRowPresentation.meta(goal: water, status: status, bundle: english, locale: Locale(identifier: "en"))
                == "Current streak: 4\nLast 30 days 87%")
        // A goal with no measured day yet shows the streak alone, never "0%".
        let fresh = GoalStatus(
            periodStart: day, periodEnd: day, progress: GoalAmount(done: 0, target: 8),
            streak: 0, longestStreak: 0, isPendingToday: true, score: nil, yearDone: 0, yearProgress: nil)
        #expect(
            GoalRowPresentation.meta(goal: water, status: fresh, bundle: english, locale: Locale(identifier: "en"))
                == "Current streak: 0")
        let sport = try #require(
            GoalDefinition(id: "goals/Spor.md", key: "spor", name: "Spor", period: .week, kind: .boolean, target: 3))
        let week = GoalStatus(
            periodStart: day, periodEnd: day, progress: GoalAmount(done: 2, target: 3),
            streak: 1, longestStreak: 1, isPendingToday: true, score: nil, yearDone: 2, yearProgress: nil)
        let meta = GoalRowPresentation.meta(
            goal: sport, status: week, bundle: turkish, locale: Locale(identifier: "tr"))
        #expect(meta == sport.period.progressTitle)
        #expect(meta?.contains("%") != true)
    }
}
