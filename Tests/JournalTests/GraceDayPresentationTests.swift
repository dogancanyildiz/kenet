import Foundation
import GoalTracking
import SwiftUI
import Testing
import VaultFormat

@testable import Journal

/// Chain days on the goal screens (decision 67): the strip's badge and the goal page's line show
/// ``GoalStatus/graceDaysAvailable`` and nothing at 0; the heatmap marks the days in
/// ``GoalStatus/graceSpentDays``. Statuses come from the history, as the screens compute them.
@MainActor struct GraceDayPresentationTests {
    private func languageBundle(_ code: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private var status: GoalStatus {
        GoalProgress.compute(
            definition: GraceDayVault.stretching, logs: GraceDayVault.stretchingLogs, today: GraceDayVault.today)
    }

    /// The history gives a balance unlike every other number of the status, so a badge reading
    /// the streak, the longest streak or the spent days would show something else.
    @Test func theBalanceIsTheStatusBalance() throws {
        let status = status
        #expect(status.streak == GraceDayVault.streak)
        #expect(status.graceSpentDays == GraceDayVault.spent)
        #expect(status.graceDaysAvailable == GraceDayVault.balance)
        #expect(GraceDayPresentation.balance(status: status) == GraceDayVault.balance)

        let badge = try #require(GraceDayPresentation.badge(status: status, locale: Locale(identifier: "tr")))
        #expect(badge.count == GraceDayVault.balance)
        let turkish = try languageBundle("tr")
        #expect(badge.label == String(localized: "\(GraceDayVault.balance) zincir günü", bundle: turkish))
    }

    /// Six done days earn nothing yet: no badge, no line. A broken chain loses its balance and
    /// shows none either, while its spent days stay in the history.
    @Test func noBalanceShowsNothing() throws {
        let goal = GraceDayVault.stretching
        let today = GraceDayVault.today
        let six = (1...6).map { GoalLog(day: today.addingDays(-$0)!, value: .boolean(true)) }
        let fresh = GoalProgress.compute(definition: goal, logs: six, today: today)
        #expect(fresh.streak == 6)
        #expect(GraceDayPresentation.balance(status: fresh) == nil)
        #expect(GraceDayPresentation.badge(status: fresh, locale: Locale(identifier: "tr")) == nil)

        // ✓×7 ✗ ✗ ✗: the first miss spends the only chain day, the second breaks the chain.
        let seven = (4...10).map { GoalLog(day: today.addingDays(-$0)!, value: .boolean(true)) }
        let broken = GoalProgress.compute(definition: goal, logs: seven, today: today)
        #expect(broken.graceDaysAvailable == 0)
        #expect(broken.graceSpentDays == [today.addingDays(-3)!])
        #expect(GraceDayPresentation.balance(status: broken) == nil)
        #expect(GraceDayPresentation.badge(status: broken, locale: Locale(identifier: "tr")) == nil)
    }

    /// The Goals list's row: the daily goal's badge carries the status balance and its label;
    /// six done days and a broken chain give none. Rows without a streak line get none either,
    /// whatever the status says.
    @Test func listRowBadgeIsTheDailyBalance() throws {
        let tr = Locale(identifier: "tr")
        let goal = GraceDayVault.stretching
        let badge = try #require(GoalRowPresentation.graceBadge(goal: goal, status: status, locale: tr))
        #expect(badge.count == GraceDayVault.balance)
        #expect(
            badge.label == String(localized: "\(GraceDayVault.balance) zincir günü", bundle: try languageBundle("tr")))

        let today = GraceDayVault.today
        let six = (1...6).map { GoalLog(day: today.addingDays(-$0)!, value: .boolean(true)) }
        let fresh = GoalProgress.compute(definition: goal, logs: six, today: today)
        #expect(fresh.streak == 6)
        #expect(GoalRowPresentation.graceBadge(goal: goal, status: fresh, locale: tr) == nil)
        let seven = (4...10).map { GoalLog(day: today.addingDays(-$0)!, value: .boolean(true)) }
        let broken = GoalProgress.compute(definition: goal, logs: seven, today: today)
        #expect(broken.graceSpentDays.count == 1)
        #expect(GoalRowPresentation.graceBadge(goal: goal, status: broken, locale: tr) == nil)

        let weekly = try #require(
            GoalDefinition(id: "goals/Spor.md", key: "spor", name: "Spor", period: .week, kind: .boolean, target: 3))
        let milestone = try #require(
            GoalDefinition(
                id: "goals/Kitap.md", key: "kitap", name: "Kitap", period: .year, kind: .milestone, target: 1))
        for other in [weekly, milestone] {
            #expect(GoalRowPresentation.graceBadge(goal: other, status: status, locale: tr) == nil, "\(other.key)")
        }
    }

    @Test func balanceTextAndRuleInBothLanguages() throws {
        let turkish = try languageBundle("tr")
        let english = try languageBundle("en")
        let tr = Locale(identifier: "tr")
        let en = Locale(identifier: "en")
        #expect(GraceDayPresentation.balanceText(2, bundle: turkish, locale: tr) == "2 zincir günü")
        #expect(GraceDayPresentation.balanceText(1, bundle: english, locale: en) == "1 streak save")
        #expect(GraceDayPresentation.balanceText(3, bundle: english, locale: en) == "3 streak saves")
        #expect(GraceDayPresentation.explanation(bundle: english, locale: en).hasPrefix("Every 7 done days"))
        #expect(GraceDayPresentation.explanation(bundle: turkish, locale: tr).hasSuffix("En çok 3."))
    }

    /// The heatmap of the vault's history: the spent days carry the chain-day mark, the free
    /// forgiveness keeps its own, and no other day of the twelve weeks carries either.
    @Test func spentDaysCarryTheChainDayMark() throws {
        let status = status
        let spent = Set(status.graceSpentDays)
        let from = try #require(GraceDayVault.today.addingDays(-83))
        let marks = GoalProgress.heatmap(
            definition: GraceDayVault.stretching, logs: GraceDayVault.stretchingLogs, from: from,
            to: GraceDayVault.today, today: GraceDayVault.today)
        var kinds: [CalendarDate: HeatmapCellKind] = [:]
        for (day, mark) in marks {
            kinds[day] = GraceDayPresentation.kind(mark: mark, isSpent: spent.contains(day))
        }
        #expect(kinds.filter { $0.value == .graceSpent }.keys.sorted() == GraceDayVault.spent)
        #expect(kinds.filter { $0.value == .forgiven }.keys.sorted() == [GraceDayVault.freeForgiven])
        #expect(kinds.values.filter { $0 == .graceSpentPartial }.isEmpty)
        let days = marks.keys.sorted()
        #expect(GraceDayPresentation.showsLegend(days: days, spent: spent))
        #expect(!GraceDayPresentation.showsLegend(days: days, spent: []))
        // Weeks before the first spent day: no legend item for a mark not in view.
        #expect(!GraceDayPresentation.showsLegend(days: days.filter { $0 < GraceDayVault.spent[0] }, spent: spent))
    }

    /// A spent day keeps its own contribution: a partial amount stays under the mark; a day that
    /// was not spent keeps its plain kind.
    @Test func spentKindKeepsTheContribution() {
        #expect(GraceDayPresentation.kind(mark: .none, isSpent: true) == .graceSpent)
        #expect(GraceDayPresentation.kind(mark: .partial, isSpent: true) == .graceSpentPartial)
        #expect(GraceDayPresentation.kind(mark: .forgivenPartial, isSpent: true) == .graceSpentPartial)
        #expect(GraceDayPresentation.kind(mark: .full, isSpent: true) == .full)
        #expect(GraceDayPresentation.kind(mark: .none, isSpent: false) == .empty)
        #expect(GraceDayPresentation.kind(mark: .partial, isSpent: false) == .partial)
        #expect(GraceDayPresentation.kind(mark: .forgiven, isSpent: false) == .forgiven)
    }

    /// The mark differs from a forgiven day by shape: the dot. The dot stays off the partial fill.
    @Test func chainDayCellShape() {
        for kind in [HeatmapCellKind.graceSpent, .graceSpentPartial] {
            #expect(kind.showsGraceDot)
            #expect(kind.usesForgivenFrame)
            #expect(kind.showsOutline)
            #expect(kind.isDrawn)
        }
        for kind in HeatmapCellKind.allCases where kind != .graceSpent && kind != .graceSpentPartial {
            #expect(!kind.showsGraceDot, "\(kind)")
        }
        #expect(!HeatmapCellKind.graceSpent.showsWell)
        #expect(HeatmapCellKind.graceSpentPartial.showsWell)
        #expect(HeatmapCellKind.graceSpentPartial.fillHeightFraction == HeatmapCellKind.partial.fillHeightFraction)
        for size: CGFloat in [10, 14, 22, 30] {
            let side = HeatmapCellKind.graceDotSide(size: size)
            #expect(side >= 3)
            let kind = HeatmapCellKind.graceSpentPartial
            let bottom = size * CGFloat(kind.graceDotCenterFraction) + side / 2
            #expect(bottom <= size * CGFloat(1 - kind.fillHeightFraction), "dot over the fill at \(size)")
        }
    }

    @Test func titlesSayTheMark() throws {
        let english = try languageBundle("en")
        #expect(String(localized: "Zincir günüyle korundu", bundle: english) == "Covered by a streak save")
        #expect(
            String(localized: "Kısmi katkı, zincir günüyle korundu", bundle: english)
                == "Partial contribution, covered by a streak save")
        #expect(String(localized: "Zincir günü", bundle: english) == "Streak save")
    }
}

/// The screens' own path: the vault's files, the index, the day model the strip and the goal page
/// read their statuses from, and the list's goal-status query.
@MainActor struct GraceDayStoreTests {
    @Test func theDayModelAndTheListGiveTheVaultsBalance() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try GraceDayVault.generate(at: context.root)
        await context.start()
        let model = GoalDayModel(store: context.store, day: GraceDayVault.today)
        await model.load()
        let stretching = try #require(model.goals.first { $0.key == "esneme" })
        let reading = try #require(model.goals.first { $0.key == "okuma" })

        let status = model.status(for: stretching)
        #expect(GraceDayPresentation.badge(status: status, locale: Locale(identifier: "tr"))?.count == 2)
        #expect(status.graceSpentDays == GraceDayVault.spent)
        #expect(GraceDayPresentation.badge(status: model.status(for: reading), locale: Locale(identifier: "tr")) == nil)

        let rows = try await context.store.computeGoalStatuses(today: GraceDayVault.today)
        let row = try #require(rows.first { $0.definition.key == "esneme" })
        #expect(GraceDayPresentation.balance(status: row.status) == 2)
        let tr = Locale(identifier: "tr")
        #expect(GoalRowPresentation.graceBadge(goal: row.definition, status: row.status, locale: tr)?.count == 2)
        let readingRow = try #require(rows.first { $0.definition.key == "okuma" })
        #expect(
            GoalRowPresentation.graceBadge(goal: readingRow.definition, status: readingRow.status, locale: tr) == nil)
    }
}
