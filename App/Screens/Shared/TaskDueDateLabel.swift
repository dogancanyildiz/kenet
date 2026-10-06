import SwiftUI
import VaultFormat

/// Due date with overdue warning color and a non-color mark when past due.
struct TaskDueDateLabel: View {
    let date: CalendarDate
    let presentation: TaskStatusPresentation
    var includeCalendarIcon = false
    var format: Date.FormatStyle = .dateTime.day().month(.abbreviated)

    var body: some View {
        dateLabel.overdueAccessibilityValue(presentation.showsOverdueCue)
            .font(.ink.meta)
            .foregroundStyle(presentation.showsOverdueCue ? Color.ink.warning : Color.ink.secondaryText)
    }

    @ViewBuilder private var dateLabel: some View {
        if presentation.showsOverdueCue {
            Label {
                Text(LocalDay.instant(for: date), format: format)
            } icon: {
                Image(systemName: "arrow.forward.circle")
            }
        } else if includeCalendarIcon {
            Label {
                Text(LocalDay.instant(for: date), format: format)
            } icon: {
                Image(systemName: "calendar")
            }
        } else {
            Text(LocalDay.instant(for: date), format: format)
        }
    }
}

extension View {
    @ViewBuilder func overdueAccessibilityValue(_ shows: Bool) -> some View {
        if shows {
            accessibilityValue(Text("Devreden"))
        } else {
            self
        }
    }
}
