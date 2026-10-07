import SwiftUI
import VaultFormat

/// Due date with overdue warning color and a non-color mark when past due.
struct TaskDueDateLabel: View {
    let date: CalendarDate
    let presentation: TaskStatusPresentation
    /// Day used for carried-over copy (``TodayPresentation.carriedOverDate``).
    var asOf: CalendarDate? = nil
    var includeCalendarIcon = false
    var format: Date.FormatStyle = .dateTime.day().month(.abbreviated)
    /// Outer callers may override (e.g. timeline tabular `.ink.time`).
    var font: Font = .ink.meta

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        dateLabel.overdueAccessibilityValue(presentation.showsOverdueCue)
            .font(font)
            .foregroundStyle(presentation.showsOverdueCue ? Color.ink.warning : Color.ink.secondaryText)
    }

    @ViewBuilder private var dateLabel: some View {
        if presentation.showsOverdueCue {
            HStack(spacing: 4) {
                Image(systemName: "arrow.forward.circle")
                    .accessibilityHidden(true)
                Text(verbatim: carriedOverText)
            }
        } else if includeCalendarIcon {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(LocalDay.instant(for: date), format: format)
            }
        } else {
            Text(LocalDay.instant(for: date), format: format)
        }
    }

    private var carriedOverText: String {
        if let asOf {
            return TodayPresentation.carriedOverDate(
                date, today: asOf, locale: locale, calendar: calendar)
        }
        return LocalDay.instant(for: date).formatted(format)
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
