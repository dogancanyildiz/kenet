import Foundation
import GoalTracking
import Testing

@testable import Kenet

/// `String(localized:locale:)` takes the language from the process and the locale only for
/// formatting: a Mac reference rendered with a Turkish environment on an English runner read
/// "Today 3/3 done", "Weekly". The page's copy follows the locale it is given, both ways round,
/// whatever the runner's own language is.
struct PresentationLocaleLanguageTests {
    private let turkish = Locale(identifier: "tr_TR")
    private let english = Locale(identifier: "en_US")

    @Test func catalogStringFollowsTheGivenLocaleNotTheProcess() {
        #expect(
            PresentationLocalization.string(localized: "Bir süredir görüşmediklerin", locale: turkish)
                == "Bir süredir görüşmediklerin")
        #expect(
            PresentationLocalization.string(localized: "Bir süredir görüşmediklerin", locale: english)
                == "People you haven’t seen in a while")
        let done = 3
        let total = 3
        #expect(
            PresentationLocalization.string(localized: "Bugün \(done)/\(total) tamam", locale: turkish)
                == "Bugün 3/3 tamam")
        #expect(
            PresentationLocalization.string(localized: "Bugün \(done)/\(total) tamam", locale: english)
                == "Today 3/3 done")
    }

    @Test func goalPeriodChipAndProgressTitleFollowTheLocale() {
        #expect(GoalListPresentation.periodChip(.week, locale: turkish) == "Haftalık")
        #expect(GoalListPresentation.periodChip(.week, locale: english) == "Weekly")
        #expect(GoalListPresentation.periodChip(.day, locale: turkish) == "Günlük")
        #expect(GoalPeriod.week.progressTitle(locale: turkish) == "Bu hafta")
        #expect(GoalPeriod.week.progressTitle(locale: english) == "This week")
        #expect(GoalListPresentation.streakText(12, locale: turkish) == "Zincir 12 gün")
        #expect(GraceDayPresentation.balanceText(2, locale: turkish) == "2 zincir günü")
    }

    @Test func anUnsupportedLanguageFallsBackToAnAppLanguage() {
        let german = Locale(identifier: "de_DE")
        let text = PresentationLocalization.string(localized: "Bir süredir görüşmediklerin", locale: german)
        #expect(["Bir süredir görüşmediklerin", "People you haven’t seen in a while"].contains(text))
    }
}
