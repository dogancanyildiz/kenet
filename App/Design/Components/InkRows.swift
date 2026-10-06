import SwiftUI
import VaultFormat

/// Ready-made task row on ``MarginRow`` (name avoids clash with model ``TaskRow``).
struct InkTaskRow: View {
    let title: String
    var state: TaskBoxState
    /// Preformatted carried-over cue from ``TodayPresentation`` (e.g. `"30 Eyl'den"`).
    var carriedOverLabel: String? = nil
    var overdueDate: Date? = nil
    /// Non-carried due date shown in secondary text color.
    var dueLabel: String? = nil
    var recurrenceLabel: String? = nil
    var showsUnknownRecurrence = false
    var showsLowPriority = false
    /// When set, drawn instead of plain ``title`` (vault links / Turkish suffixes).
    var segments: [InkLinkSegment]? = nil
    var openURL: ((URL) -> Void)? = nil
    var action: (() -> Void)? = nil
    var accessibilityLabelKey: LocalizedStringKey = "Görevi tamamla"

    var body: some View {
        MarginRow(kind: .vault) {
            TaskBox(state: state, action: action, accessibilityLabelKey: accessibilityLabelKey)
        } primary: {
            Group {
                if let segments, !state.isCompleted {
                    InkLinkedText(segments: segments, openURL: openURL)
                } else {
                    Text(verbatim: title)
                        .foregroundStyle(state.isCompleted ? Color.ink.secondaryText : Color.ink.text)
                }
            }
        } secondary: {
            if !state.isCompleted {
                secondaryLine
            }
        }
    }

    @ViewBuilder private var secondaryLine: some View {
        let hasCarried = carriedOverLabel.map { !$0.isEmpty } == true
        let hasDue = dueLabel.map { !$0.isEmpty } == true && !hasCarried
        let hasRecurrence = recurrenceLabel.map { !$0.isEmpty } == true || showsUnknownRecurrence
        if hasCarried || hasDue || hasRecurrence || showsLowPriority || overdueDate != nil {
            HStack(spacing: 8) {
                if let carriedOverLabel, !carriedOverLabel.isEmpty {
                    carriedLabel(carriedOverLabel)
                } else if let overdueDate {
                    overdueLabel(overdueDate)
                } else if let dueLabel, !dueLabel.isEmpty {
                    Text(verbatim: dueLabel)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                if let recurrenceLabel, !recurrenceLabel.isEmpty {
                    Label {
                        Text(verbatim: recurrenceLabel)
                    } icon: {
                        Image(systemName: "repeat")
                    }
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                } else if showsUnknownRecurrence {
                    Label("Tanınmayan tekrar", systemImage: "repeat")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                if showsLowPriority {
                    TaskPriorityMark(priority: .low)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
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
    var metaText: String? = nil
    var onIncrement: (() -> Void)? = nil
    var onValueTap: (() -> Void)? = nil
    var onMarkTap: (() -> Void)? = nil
    var showsPlus: Bool = true
    var incrementLabel: LocalizedStringKey = "Artır"
    var enterAmountLabel: LocalizedStringKey = "Miktar gir"

    @ScaledMetric(relativeTo: .body) private var plusSide = InkSize.plus

    var body: some View {
        MarginRow(kind: .vault) {
            if let onMarkTap {
                Button(action: onMarkTap) {
                    GoalRing(progress: progress, isBoolean: isBoolean)
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(incrementLabel))
            } else {
                GoalRing(progress: progress, isBoolean: isBoolean)
            }
        } primary: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name)
                    .foregroundStyle(progress >= 1 ? Color.ink.secondaryText : Color.ink.text)
                if let metaText, !metaText.isEmpty {
                    Text(verbatim: metaText)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
        } trailing: {
            HStack(spacing: 8) {
                if let valueText {
                    if let onValueTap {
                        Button(action: onValueTap) {
                            Text(verbatim: valueText)
                                .font(.ink.value)
                                .foregroundStyle(.ink.secondaryText)
                                // Hit area grows down/out; text stays on the first-line baseline.
                                .frame(
                                    minWidth: TapTarget.minimumLength,
                                    minHeight: TapTarget.minimumLength, alignment: .topTrailing
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(enterAmountLabel))
                    } else {
                        Text(verbatim: valueText)
                            .font(.ink.value)
                            .foregroundStyle(.ink.secondaryText)
                    }
                }
                if showsPlus, let onIncrement {
                    Button(action: onIncrement) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(
                                progress >= 1 ? Color.ink.secondaryText : Color.ink.accent
                            )
                            .frame(width: plusSide, height: plusSide)
                            .background {
                                ZStack {
                                    Circle().fill(Color.ink.control)
                                    Circle().inset(by: InkStroke.control).fill(Color.ink.paper)
                                }
                            }
                            .frame(
                                minWidth: TapTarget.minimumLength,
                                minHeight: TapTarget.minimumLength, alignment: .top
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(incrementLabel))
                }
            }
        }
        .accessibilityAction(named: Text(enterAmountLabel)) {
            onValueTap?()
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
