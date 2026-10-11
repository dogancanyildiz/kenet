import GoalTracking
import SwiftUI

extension GoalPeriod {
    var title: String {
        switch self {
        case .day: String(localized: "Günlük hedef")
        case .week: String(localized: "Haftalık")
        case .year: String(localized: "Yıllık")
        }
    }
    var progressTitle: String {
        switch self {
        case .day: String(localized: "Bu gün")
        case .week: String(localized: "Bu hafta")
        case .year: String(localized: "Bu yıl")
        }
    }
}
extension GoalKind {
    var title: String {
        switch self {
        case .boolean: String(localized: "Evet / hayır")
        case .number: String(localized: "Sayı")
        case .milestone: String(localized: "Kilometre taşı")
        }
    }
}
extension GoalDayMark {
    var title: LocalizedStringKey {
        switch self {
        case .none: "Katkı yok"
        case .partial: "Kısmi katkı"
        case .full: "Tam katkı"
        case .forgiven: "Affedildi"
        }
    }
}

enum GoalScoreCopy {
    /// "Son 30 gün %87" / "Last 30 days 87%". `bundle` selects the language.
    static func sentence(_ score: Int, bundle: Bundle = .main, locale: Locale = .current) -> String {
        String(localized: "Son 30 gün \(score)", bundle: bundle, locale: locale)
    }
}

struct GoalProgressLabel: View {
    let goal: GoalDefinition
    let status: GoalStatus
    var body: some View {
        HStack(spacing: 6) {
            if goal.kind == .milestone {
                Text(status.completionDate == nil ? "Yapılmadı" : "Yapıldı")
                if let day = status.completionDate {
                    Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
                }
            } else {
                Text(verbatim: goal.period.progressTitle)
                Text(verbatim: status.progress.done.formatted() + "/" + goal.target.formatted())
                    .font(.ink.value)
                    .monospacedDigit()
                if let unit = goal.unit { Text(verbatim: unit) }
            }
        }
        .font(.ink.meta)
        .foregroundStyle(Color.ink.secondaryText)
    }
}

enum GoalRowPresentation {
    static func progress(goal: GoalDefinition, status: GoalStatus) -> Double {
        if goal.kind == .milestone {
            return status.completionDate == nil ? 0 : 1
        }
        return status.progress.fraction
    }

    static func valueText(goal: GoalDefinition, status: GoalStatus) -> String? {
        if goal.kind == .milestone {
            return nil
        }
        var text = status.progress.done.formatted() + "/" + goal.target.formatted()
        if let unit = goal.unit, !unit.isEmpty { text += " " + unit }
        return text
    }

    /// Meta under the name: streak and score for daily goals, period label for week/year.
    static func meta(
        goal: GoalDefinition, status: GoalStatus, bundle: Bundle = .main, locale: Locale = .current
    ) -> String? {
        if goal.kind == .milestone {
            if let day = status.completionDate {
                return LocalDay.instant(for: day).formatted(.dateTime.day().month().year())
            }
            return String(localized: "Yapılmadı", bundle: bundle, locale: locale)
        }
        if goal.period == .day {
            let streak = String(localized: "Güncel zincir: \(status.streak)", bundle: bundle, locale: locale)
            guard let score = status.score else { return streak }
            // Own line so the percent does not wrap off "Son 30 gün" in a narrow row.
            return streak + "\n" + GoalScoreCopy.sentence(score, bundle: bundle, locale: locale)
        }
        return goal.period.progressTitle
    }

    /// Thin determinate bar for yearly goals only.
    static func barFraction(goal: GoalDefinition, status: GoalStatus) -> Double? {
        guard goal.kind != .milestone, goal.period == .year else { return nil }
        return InkProgressMath.ratio(done: status.progress.done, target: goal.target)
    }
}
