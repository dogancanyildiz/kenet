import Foundation
import GoalTracking
import VaultFormat

/// Pure list / detail copy and tally math for Goals (unit-tested). Core status stays unchanged.
enum GoalListPresentation {
    /// Period chip on list and detail: Günlük / Haftalık / Yıllık.
    static func periodChip(_ period: GoalPeriod, bundle: Bundle = .main, locale: Locale = .current)
        -> String
    {
        let key: String.LocalizationValue =
            switch period {
            case .day: "Günlük"
            case .week: "Haftalık"
            case .year: "Yıllık"
            }
        return String(localized: key, bundle: bundle, locale: locale)
    }

    /// Kind tabs on create / edit: İşaret | Sayı | Kilometre taşı.
    static func kindTab(_ kind: GoalKind, bundle: Bundle = .main, locale: Locale = .current) -> String {
        let key: String.LocalizationValue =
            switch kind {
            case .boolean: "İşaret"
            case .number: "Sayı"
            case .milestone: "Kilometre taşı"
            }
        return String(localized: key, bundle: bundle, locale: locale)
    }

    /// Unclamped percent for the ring center (30/20 → 150).
    static func percent(done: Double, target: Double) -> Int {
        guard target > 0, done.isFinite, target.isFinite else { return 0 }
        return Int((done / target * 100).rounded())
    }

    static func percentLabel(done: Double, target: Double) -> String {
        "%\(percent(done: done, target: target))"
    }

    /// Remaining amount; nil when complete or milestone.
    static func remainingAmount(goal: GoalDefinition, status: GoalStatus) -> Double? {
        guard goal.kind != .milestone else { return nil }
        let left = max(0, goal.target - status.progress.done)
        return left > 0 ? left : nil
    }

    /// "Bugün · 8 sayfa kaldı" / "Today · 8 pages left". Nil when complete or milestone.
    static func remainingText(
        goal: GoalDefinition, status: GoalStatus, bundle: Bundle = .main, locale: Locale = .current
    ) -> String? {
        guard let left = remainingAmount(goal: goal, status: status) else { return nil }
        let amount = left.formatted(.number.precision(.fractionLength(0)).locale(locale))
        let piece = goal.unit.map { "\(amount) \($0)" } ?? amount
        if goal.period == .day {
            return String(localized: "Bugün · \(piece) kaldı", bundle: bundle, locale: locale)
        }
        return String(localized: "\(piece) kaldı", bundle: bundle, locale: locale)
    }

    /// "Zincir 12 gün" / "Streak 12 days".
    static func streakText(
        _ streak: Int, bundle: Bundle = .main, locale: Locale = .current
    ) -> String {
        String(localized: "Zincir \(streak) gün", bundle: bundle, locale: locale)
    }

    /// Open goals first, then complete; each group by name (rule 6).
    static func ordered(
        _ goals: [GoalDefinition], status: (GoalDefinition) -> GoalStatus
    ) -> [GoalDefinition] {
        GoalStripPresentation.ordered(goals, status: status)
    }

    /// Yearly pace line: target / 12.
    static func yearlyPace(target: Double) -> Double { target / 12 }

    /// Last 7 days ending at `today`, oldest first.
    static func tallyDays(
        goal: GoalDefinition, logs: [GoalLog], today: CalendarDate,
        graceSpent: Set<CalendarDate> = []
    ) -> [GoalTallyDay] {
        guard goal.kind != .milestone, goal.period == .day,
            let start = today.addingDays(-6)
        else { return [] }
        let marks = GoalProgress.heatmap(
            definition: goal, logs: logs, from: start, to: today, today: today)
        return (0..<7).compactMap { offset -> GoalTallyDay? in
            guard let day = start.addingDays(offset) else { return nil }
            let mark = marks[day] ?? .none
            let kind = GraceDayPresentation.kind(mark: mark, isSpent: graceSpent.contains(day))
            let fill: GoalTallyDay.Fill =
                switch kind {
                case .full, .today: .filled
                case .partial: .partial
                case .forgiven, .forgivenPartial, .graceSpent, .graceSpentPartial: .forgiven
                case .empty, .future: .empty
                }
            return GoalTallyDay(day: day, fill: fill, isToday: day == today)
        }
    }

    /// Calendar-year month bars for a yearly goal (future months flagged).
    static func yearMonthBars(
        goal: GoalDefinition, logs: [GoalLog], today: CalendarDate
    ) -> [GoalYearMonthBar] {
        guard goal.kind != .milestone, goal.period == .year else { return [] }
        let yearStart = today.startOfYear
        // Last log wins per day (same rule as GoalProgress); App cannot call Core's internal amounts.
        var perDay: [CalendarDate: Double] = [:]
        for log in logs where log.day.year == today.year && log.day <= today {
            switch (goal.kind, log.value) {
            case (.number, .number(let value)) where value.isFinite && value >= 0:
                perDay[log.day] = value
            case (.boolean, .boolean(let done)):
                perDay[log.day] = done ? 1 : 0
            default:
                break
            }
        }
        var totals = [Double](repeating: 0, count: 12)
        for (day, value) in perDay { totals[day.month - 1] += value }
        let peak = max(totals.max() ?? 0, 1)
        return (0..<12).compactMap { index in
            guard let start = yearStart.addingMonths(index) else { return nil }
            let isFuture = start > today.startOfMonth
            return GoalYearMonthBar(
                month: start.month,
                total: isFuture ? 0 : totals[index],
                fraction: isFuture ? 0 : totals[index] / peak,
                isFuture: isFuture
            )
        }
    }

    /// Forgiven days in the heatmap window (past only), newest last.
    static func forgivenDays(
        goal: GoalDefinition, logs: [GoalLog], today: CalendarDate, span: Int = 90
    ) -> [CalendarDate] {
        guard goal.period == .day, goal.kind != .milestone,
            let start = today.addingDays(-(span - 1))
        else { return [] }
        let marks = GoalProgress.heatmap(
            definition: goal, logs: logs, from: start, to: today, today: today)
        return marks.keys.filter { marks[$0]?.isForgiven == true }.sorted()
    }
}

struct GoalTallyDay: Equatable, Sendable {
    enum Fill: Equatable, Sendable { case empty, partial, filled, forgiven }
    let day: CalendarDate
    let fill: Fill
    let isToday: Bool

    var heatmapKind: HeatmapCellKind {
        switch fill {
        case .empty: .empty
        case .partial: .partial
        case .filled: .full
        case .forgiven: .forgiven
        }
    }
}

struct GoalYearMonthBar: Equatable, Sendable {
    let month: Int
    let total: Double
    let fraction: Double
    let isFuture: Bool
}
