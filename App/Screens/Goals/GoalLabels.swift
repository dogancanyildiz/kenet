import GoalTracking
import SwiftUI

extension GoalPeriod {
    var title: LocalizedStringKey {
        switch self {
        case .day: "Günlük hedef"
        case .week: "Haftalık"
        case .year: "Yıllık"
        }
    }
    var progressTitle: LocalizedStringKey {
        switch self {
        case .day: "Bu gün"
        case .week: "Bu hafta"
        case .year: "Bu yıl"
        }
    }
}
extension GoalKind {
    var title: LocalizedStringKey {
        switch self {
        case .boolean: "Evet / hayır"
        case .number: "Sayı"
        case .milestone: "Kilometre taşı"
        }
    }
}
extension GoalDayMark {
    var title: LocalizedStringKey {
        switch self {
        case .none: "Katkı yok"
        case .partial: "Kısmi katkı"
        case .full: "Tam katkı"
        }
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
                Text(goal.period.progressTitle)
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

    static func meta(goal: GoalDefinition, status: GoalStatus) -> String? {
        if goal.kind == .milestone {
            if let day = status.completionDate {
                return LocalDay.instant(for: day).formatted(.dateTime.day().month().year())
            }
            return String(localized: "Yapılmadı")
        }
        if goal.period == .day {
            return String(localized: "Güncel zincir: \(status.streak)")
        }
        let periodLabel: String =
            switch goal.period {
            case .day: String(localized: "Bu gün")
            case .week: String(localized: "Bu hafta")
            case .year: String(localized: "Bu yıl")
            }
        return periodLabel + " · " + status.progress.done.formatted() + "/" + goal.target.formatted()
    }
}
