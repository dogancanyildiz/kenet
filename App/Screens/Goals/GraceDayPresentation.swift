import GoalTracking
import SwiftUI
import VaultFormat

/// Chain days (decision 67) as the goal screens show them (unit-tested). Every number comes from
/// ``GoalStatus``: the balance from ``GoalStatus/graceDaysAvailable``, the spent days from
/// ``GoalStatus/graceSpentDays``. A balance of 0 shows nothing.
enum GraceDayPresentation {
    /// The balance the Today strip's badge and the goal page's line show; nil when there is none.
    static func balance(status: GoalStatus) -> Int? {
        status.graceDaysAvailable > 0 ? status.graceDaysAvailable : nil
    }

    /// "2 zincir günü" / "2 streak saves". `bundle` selects the language.
    static func balanceText(_ count: Int, bundle: Bundle = .main, locale: Locale = .current) -> String {
        String(localized: "\(count) zincir günü", bundle: bundle, locale: locale)
    }

    /// The one-sentence rule under the goal page's balance line.
    static func explanation(bundle: Bundle = .main, locale: Locale = .current) -> String {
        String(localized: rule, bundle: bundle, locale: locale)
    }

    private static let rule: String.LocalizationValue =
        "Zincirdeki her 7 yapılmış gün 1 zincir günü kazandırır; kaçırılan gün zincir günüyle korunur. En çok 3."

    /// The strip's badge for `status`; nil with no balance.
    static func badge(status: GoalStatus, locale: Locale) -> GraceDayBadge? {
        balance(status: status).map { count in
            GraceDayBadge(
                count: count,
                label: balanceText(count, bundle: PresentationLocalization.bundle(locale), locale: locale))
        }
    }

    /// The heatmap cell of a day with `mark`: a day covered by a spent chain day keeps its own
    /// contribution under the chain-day mark. A full day is never a miss, so it stays full.
    static func kind(mark: GoalDayMark, isSpent: Bool) -> HeatmapCellKind {
        guard isSpent, mark != .full else { return mark.heatmapKind }
        return mark == .partial || mark == .forgivenPartial ? .graceSpentPartial : .graceSpent
    }

    /// What VoiceOver says for that cell.
    static func title(mark: GoalDayMark, isSpent: Bool) -> LocalizedStringKey {
        switch kind(mark: mark, isSpent: isSpent) {
        case .graceSpent: "Zincir günüyle korundu"
        case .graceSpentPartial: "Kısmi katkı, zincir günüyle korundu"
        default: mark.title
        }
    }

    /// Whether a heatmap over `days` needs the chain-day legend item: one of them was covered.
    static func showsLegend(days: [CalendarDate], spent: Set<CalendarDate>) -> Bool {
        !spent.isEmpty && days.contains { spent.contains($0) }
    }
}
