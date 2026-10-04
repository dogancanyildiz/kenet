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
    var title: LocalizedStringKey { self == .boolean ? "Evet / hayır" : "Sayı" }
}
extension GoalDayMark {
    var title: LocalizedStringKey {
        switch self {
        case .none: "Katkı yok"
        case .partial: "Kısmi katkı"
        case .full: "Tam katkı"
        }
    }
    var color: Color {
        switch self {
        case .none: .secondary.opacity(0.12)
        case .partial: .green.opacity(0.35)
        case .full: .green.opacity(0.9)
        }
    }
}
struct GoalProgressLabel: View {
    let goal: GoalDefinition
    let status: GoalStatus
    var body: some View {
        HStack {
            Text(goal.period.progressTitle)
            Text(verbatim: status.progress.done.formatted() + "/" + goal.target.formatted())
            if let unit = goal.unit { Text(verbatim: unit) }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
struct GoalCard: View {
    let goal: GoalDefinition
    let status: GoalStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: goal.name).font(.headline)
            Text(goal.period.title).font(.caption).foregroundStyle(.secondary)
            if goal.period == .day {
                Text("Güncel zincir: \(status.streak)").font(.subheadline)
            } else {
                GoalProgressLabel(goal: goal, status: status)
            }
            if let year = status.yearProgress {
                ProgressView(value: year.fraction).accessibilityLabel("Yıllık ilerleme")
            }
        }.padding(.vertical, 6)
    }
}
