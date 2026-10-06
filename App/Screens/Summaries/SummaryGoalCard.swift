import GoalTracking
import Summaries
import SwiftUI

struct SummaryGoalCard: View {
    let goals: [SummaryGoal]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: String(localized: "Hedefler"))
            ForEach(goals, id: \.definition.id) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: goal.definition.name)
                        .font(.ink.content)
                        .foregroundStyle(Color.ink.text)
                    HStack(alignment: .firstTextBaseline) {
                        Text(
                            LocalizedStringKey(
                                goal.definition.period == .year ? "Yıl başından" : "Dönemde")
                        )
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        Spacer()
                        Text(verbatim: goal.progress.done.formatted())
                            .font(.ink.largeNumber)
                            .foregroundStyle(Color.ink.text)
                        Text(
                            verbatim: "/ " + goal.progress.target.formatted()
                                + (goal.definition.unit.map { " " + $0 } ?? "")
                        )
                        .font(.ink.value)
                        .foregroundStyle(Color.ink.secondaryText)
                        SummaryChangeBadge(value: goal.change)
                    }
                    InkProgress(
                        kind: .determinate(
                            completed: Int(goal.progress.done.rounded()),
                            total: max(1, Int(goal.progress.target.rounded())),
                            label: nil))
                    if goal.definition.kind != .milestone {
                        SummaryMetric(
                            title: "Dönem sonu zincir", value: goal.streak, change: goal.streakChange)
                    } else if let date = goal.completionDate {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
            }
            if goals.isEmpty {
                Text("Henüz hedef yok")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
    }
}
