import GoalTracking
import Summaries
import SwiftUI

struct SummaryGoalCard: View {
    let goals: [SummaryGoal]
    var body: some View {
        GroupBox("Hedefler") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(goals, id: \.definition.id) { goal in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: goal.definition.name).font(.headline)
                        HStack {
                            Text(LocalizedStringKey(goal.definition.period == .year ? "Yıl başından" : "Dönemde")).font(
                                .caption)
                            Spacer()
                            Text(verbatim: goal.progress.done.formatted() + " / " + goal.progress.target.formatted())
                            if let unit = goal.definition.unit { Text(verbatim: unit).font(.caption) }
                            SummaryChangeBadge(value: goal.change)
                        }
                        ProgressView(value: goal.progress.fraction)
                        if goal.definition.kind != .milestone {
                            SummaryMetric(title: "Dönem sonu zincir", value: goal.streak, change: goal.streakChange)
                                .font(.caption)
                        } else if let date = goal.completionDate {
                            Text(LocalDay.instant(for: date), format: .dateTime.day().month().year()).font(.caption)
                        }
                    }
                }
                if goals.isEmpty { Text("Henüz hedef yok").foregroundStyle(.secondary) }
            }.padding(.top, 8)
        }
    }
}
