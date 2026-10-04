import GoalTracking
import SwiftUI
import VaultFormat

struct GoalHeatmap: View {
    let goal: GoalDefinition
    let logs: [GoalLog]
    let today: CalendarDate
    let select: (CalendarDate) -> Void
    var body: some View {
        let start = today.addingDays(-83) ?? today
        let marks = GoalProgress.heatmap(definition: goal, logs: logs, from: start, to: today)
        let dates = (0..<84).compactMap { start.addingDays($0) }.filter { $0 <= today }
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(dates, id: \.self) { day in
                    let mark = marks[day] ?? .none
                    Button {
                        select(day)
                    } label: {
                        RoundedRectangle(cornerRadius: 3).fill(mark.color).frame(height: 18)
                    }.buttonStyle(.plain)
                        .accessibilityLabel(Text(LocalDay.instant(for: day), format: .dateTime.day().month().year()))
                        .accessibilityValue(Text(mark.title))
                        .help(Text(LocalDay.instant(for: day), format: .dateTime.day().month().year()))
                }
            }
            HStack {
                ForEach([GoalDayMark.none, .partial, .full], id: \.rawValue) { mark in
                    HStack(spacing: 4) {
                        Circle().fill(mark.color).frame(width: 8, height: 8)
                        Text(mark.title)
                    }
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
