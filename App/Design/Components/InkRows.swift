import SwiftUI
import VaultFormat

/// Ready-made task row on ``MarginRow`` (name avoids clash with model ``TaskRow``).
struct InkTaskRow: View {
    let title: String
    var state: TaskBoxState
    /// Preformatted carried-over cue from ``TodayPresentation`` (e.g. `"30 Eyl'den"`).
    var carriedOverLabel: String? = nil
    var overdueDate: Date? = nil
    /// When set, drawn instead of plain ``title`` (vault links / Turkish suffixes).
    var segments: [InkLinkSegment]? = nil
    var openURL: ((URL) -> Void)? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        MarginRow(kind: .vault) {
            TaskBox(state: state, action: action)
        } primary: {
            Group {
                if let segments {
                    InkLinkedText(segments: segments, openURL: openURL)
                } else {
                    Text(verbatim: title)
                        .foregroundStyle(state.isCompleted ? Color.ink.secondaryText : Color.ink.text)
                        .strikethrough(false)
                }
            }
            .opacity(state.isCompleted && segments != nil ? 0.7 : 1)
        } secondary: {
            if !state.isCompleted {
                if let carriedOverLabel, !carriedOverLabel.isEmpty {
                    carriedLabel(carriedOverLabel)
                } else if let overdueDate {
                    overdueLabel(overdueDate)
                }
            }
        }
    }

    private func carriedLabel(_ text: String) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "arrow.forward.circle")
        }
        .font(.ink.meta)
        .foregroundStyle(.ink.warning)
        .accessibilityLabel(Text("Devreden"))
        .accessibilityValue(Text(verbatim: text))
    }

    private func overdueLabel(_ date: Date) -> some View {
        Label {
            Text(date, format: .dateTime.day().month(.abbreviated))
        } icon: {
            Image(systemName: "arrow.forward.circle")
        }
        .font(.ink.meta)
        .foregroundStyle(.ink.warning)
        .accessibilityLabel(Text("Devreden"))
        .accessibilityValue(
            Text(date, format: .dateTime.day().month(.abbreviated).year())
        )
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
