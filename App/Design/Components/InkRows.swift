import SwiftUI
import VaultFormat

/// Ready-made task row on ``MarginRow`` (name avoids clash with model ``TaskRow``).
struct InkTaskRow: View {
    let title: String
    var state: TaskBoxState
    var overdueDate: Date? = nil
    var action: (() -> Void)? = nil

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.clockNow) private var clockNow

    var body: some View {
        MarginRow(kind: .vault) {
            TaskBox(state: state, action: action)
        } primary: {
            Text(verbatim: title)
                .foregroundStyle(state.isCompleted ? Color.ink.secondaryText : Color.ink.text)
                .strikethrough(false)
        } secondary: {
            if let overdueDate, !state.isCompleted {
                overdueLabel(overdueDate)
            }
        }
    }

    private func overdueLabel(_ date: Date) -> some View {
        let due = LocalDay.today(at: date, timeZone: calendar.timeZone)
        let today = LocalDay.today(at: clockNow(), timeZone: calendar.timeZone)
        let text = TodayPresentation.carriedOverDate(
            due, today: today, locale: locale, calendar: calendar)
        return HStack(spacing: 4) {
            Image(systemName: "arrow.forward.circle")
            Text(verbatim: text)
        }
        .font(.ink.meta)
        .foregroundStyle(.ink.warning)
        .accessibilityLabel(Text("Devreden"))
        .accessibilityValue(Text(verbatim: text))
    }
}

/// Goal row: ring, name, trailing value + one-tap plus.
struct InkGoalRow: View {
    let name: String
    var progress: Double
    var isBoolean: Bool = false
    var valueText: String? = nil
    var onIncrement: (() -> Void)? = nil

    var body: some View {
        MarginRow(kind: .vault) {
            GoalRing(progress: progress, isBoolean: isBoolean)
        } primary: {
            Text(verbatim: name)
                .foregroundStyle(progress >= 1 ? Color.ink.secondaryText : Color.ink.text)
        } trailing: {
            HStack(spacing: 8) {
                if let valueText {
                    Text(verbatim: valueText)
                        .font(.ink.value)
                        .foregroundStyle(.ink.secondaryText)
                }
                if let onIncrement {
                    Button(action: onIncrement) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.ink.accent)
                            .frame(width: InkSize.plus, height: InkSize.plus)
                            .overlay {
                                Circle().strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
                            }
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Artır"))
                }
            }
        }
    }
}

/// Event row: tabular time in the gutter, linked vault text.
struct InkEventRow: View {
    var time: String?
    let segments: [InkLinkSegment]
    var openURL: ((URL) -> Void)? = nil

    var body: some View {
        MarginRow(kind: .vault, time: time) {
            InkLinkedText(segments: segments, openURL: openURL)
        }
    }
}

/// Calendar row: tabular time, sans body (external source).
struct InkCalendarRow: View {
    var time: String?
    let title: String

    var body: some View {
        MarginRow(kind: .external, time: time) {
            Text(verbatim: title)
                .foregroundStyle(.ink.text)
        }
    }
}
