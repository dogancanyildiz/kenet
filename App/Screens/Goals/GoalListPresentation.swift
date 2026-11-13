import Foundation
import GoalTracking
import VaultFormat

/// Pure list / detail copy and tally math for Goals (unit-tested). Core status stays unchanged.
enum GoalListPresentation {
    /// Period chip on list and detail: Günlük / Haftalık / Yıllık.
    static func periodChip(_ period: GoalPeriod, bundle: Bundle? = nil, locale: Locale = .current)
        -> String
    {
        let key: String.LocalizationValue =
            switch period {
            case .day: "Günlük"
            case .week: "Haftalık"
            case .year: "Yıllık"
            }
        return String(localized: key, bundle: bundle ?? PresentationLocalization.bundle(locale), locale: locale)
    }

    /// Kind tabs on create / edit: İşaret | Sayı | Kilometre taşı.
    static func kindTab(_ kind: GoalKind, bundle: Bundle? = nil, locale: Locale = .current) -> String {
        let key: String.LocalizationValue =
            switch kind {
            case .boolean: "İşaret"
            case .number: "Sayı"
            case .milestone: "Kilometre taşı"
            }
        return String(localized: key, bundle: bundle ?? PresentationLocalization.bundle(locale), locale: locale)
    }

    /// Unclamped percent for the ring center (30/20 → 150).
    static func percent(done: Double, target: Double) -> Int {
        guard target > 0, done.isFinite, target.isFinite else { return 0 }
        return Int((done / target * 100).rounded())
    }

    /// Locale-aware percent ("60%" / "%60").
    static func percentLabel(
        done: Double, target: Double, locale: Locale = .current
    ) -> String {
        let ratio = target > 0 && done.isFinite && target.isFinite ? done / target : 0
        return ratio.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// Score cell: 87 → "87%" / "%87".
    static func scorePercentLabel(_ score: Int, locale: Locale = .current) -> String {
        (Double(score) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// VoiceOver summary for a 7-day tally.
    static func tallySummary(
        _ days: [GoalTallyDay], bundle: Bundle? = nil, locale: Locale = .current
    ) -> String {
        let done = days.filter { $0.fill == .filled || $0.fill == .partial }.count
        let forgiven = days.filter { $0.fill == .forgiven }.count
        let total = days.count
        if forgiven > 0 {
            return String(
                localized: "\(total) günün \(done)'i yapıldı, \(forgiven) affedildi",
                bundle: bundle ?? PresentationLocalization.bundle(locale), locale: locale)
        }
        return String(
            localized: "\(total) günün \(done)'i yapıldı", bundle: bundle ?? PresentationLocalization.bundle(locale),
            locale: locale)
    }

    /// VoiceOver summary for yearly mini bars.
    static func yearBarsSummary(
        _ bars: [GoalYearMonthBar], bundle: Bundle? = nil, locale: Locale = .current
    ) -> String {
        let past = bars.filter { !$0.isFuture }
        let total = past.reduce(0.0) { $0 + $1.total }
        let amount = total.formatted(.number.precision(.fractionLength(0)).locale(locale))
        return String(
            localized: "\(past.count) ayda \(amount)", bundle: bundle ?? PresentationLocalization.bundle(locale),
            locale: locale)
    }

    /// Remaining amount; nil when complete or milestone.
    static func remainingAmount(goal: GoalDefinition, status: GoalStatus) -> Double? {
        guard goal.kind != .milestone else { return nil }
        let left = max(0, goal.target - status.progress.done)
        return left > 0 ? left : nil
    }

    /// "Bugün · 8 sayfa kaldı" / "Today · 8 pages left". Nil when complete or milestone.
    static func remainingText(
        goal: GoalDefinition, status: GoalStatus, bundle: Bundle? = nil, locale: Locale = .current
    ) -> String? {
        guard let left = remainingAmount(goal: goal, status: status) else { return nil }
        let amount = left.formatted(.number.precision(.fractionLength(0)).locale(locale))
        let piece = goal.unit.map { "\(amount) \($0)" } ?? amount
        if goal.period == .day {
            return String(
                localized: "Bugün · \(piece) kaldı", bundle: bundle ?? PresentationLocalization.bundle(locale),
                locale: locale)
        }
        return String(
            localized: "\(piece) kaldı", bundle: bundle ?? PresentationLocalization.bundle(locale), locale: locale)
    }

    /// "Zincir 12 gün" / "Streak 12 days".
    static func streakText(
        _ streak: Int, bundle: Bundle? = nil, locale: Locale = .current
    ) -> String {
        String(
            localized: "Zincir \(streak) gün", bundle: bundle ?? PresentationLocalization.bundle(locale), locale: locale
        )
    }

    /// Compact column label under a weekly goal value: "bu hafta" / "this week".
    static func columnWeekLabel(locale: Locale = .current) -> String {
        PresentationLocalization.string(localized: "bu hafta", locale: locale)
    }

    /// Compact column streak: "zincir 12" / "streak 12".
    static func columnStreakLabel(_ streak: Int, locale: Locale = .current) -> String {
        PresentationLocalization.string(localized: "zincir \(streak)", locale: locale)
    }

    /// Period progress finished (milestone uses completion date via ``GoalRowPresentation/progress``).
    static func isComplete(goal: GoalDefinition, status: GoalStatus) -> Bool {
        GoalRowPresentation.progress(goal: goal, status: status) >= 1
    }

    /// Boolean or milestone: list trailing control is mark / unmark, not amount.
    static func isBooleanMark(_ kind: GoalKind) -> Bool {
        kind == .boolean || kind == .milestone
    }

    /// VoiceOver label for a list or column row: "name, value/meta, badge".
    static func accessibilityLabel(
        goal: GoalDefinition, status: GoalStatus, bundle: Bundle? = nil, locale: Locale = .current
    ) -> String {
        let detail =
            GoalRowPresentation.valueText(goal: goal, status: status, locale: locale)
            ?? GoalRowPresentation.meta(goal: goal, status: status, bundle: bundle, locale: locale)
        let badge = GoalRowPresentation.graceBadge(goal: goal, status: status, locale: locale)?.label
        return [goal.name, detail, badge].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Open / mark hint for list card and column row. Pass `markedToday` on the phone card so a
    /// marked milestone says "İşareti kaldır"; omit it in the column (always "Bugünü işaretle").
    static func listOpenHint(
        kind: GoalKind, markedToday: Bool? = nil, bundle: Bundle? = nil, locale: Locale = .current
    ) -> String {
        let key: String.LocalizationValue =
            if kind == .milestone {
                markedToday == true ? "İşareti kaldır" : "Bugünü işaretle"
            } else {
                "Ayrıntıları göster"
            }
        return String(
            localized: key, bundle: bundle ?? PresentationLocalization.bundle(locale), locale: locale)
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
