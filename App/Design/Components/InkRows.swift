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

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.clockNow) private var clockNow

    var body: some View {
        MarginRow(kind: .vault) {
            TaskBox(state: state, action: action, accessibilityLabel: accessibilityLabelKey)
        } primary: {
            Group {
                if let segments {
                    // Completed rows keep their links; only the plain runs fade.
                    InkLinkedText(segments: segments, isMuted: state.isCompleted, openURL: openURL)
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

/// Goal row: ring, name, optional streak/series meta, trailing value + one-tap plus.
struct InkGoalRow: View {
    let name: String
    var progress: Double
    var isBoolean: Bool = false
    /// Streak / series / period line under the name (app meta, sans).
    var meta: String? = nil
    /// Optional thin ratio bar (yearly goals); counter-less ``InkProgress/Kind/fraction``.
    var barFraction: Double? = nil
    var valueText: String? = nil
    var onIncrement: (() -> Void)? = nil
    var onValueTap: (() -> Void)? = nil
    var onMarkTap: (() -> Void)? = nil
    var showsPlus: Bool = true
    var incrementLabel: LocalizedStringKey = "Artır"
    var enterAmountLabel: LocalizedStringKey = "Miktar gir"

    @ScaledMetric(relativeTo: .body) private var plusSide = InkSize.plus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            goalRow
            if let barFraction {
                InkProgress(kind: .fraction(barFraction))
                    .padding(.leading, InkSpacing.gutter + 10)
            }
        }
        .modifier(GoalValueAccessibilityAction(action: onValueTap, label: enterAmountLabel))
    }

    private var goalRow: some View {
        MarginRow(kind: .vault) {
            mark
        } primary: {
            Text(verbatim: name)
                .foregroundStyle(progress >= 1 ? Color.ink.secondaryText : Color.ink.text)
        } secondary: {
            if let meta, !meta.isEmpty {
                Text(verbatim: meta)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
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
                        .accessibilityLabel(Text(verbatim: name))
                        .accessibilityValue(Text(verbatim: valueText))
                        .accessibilityHint(Text(enterAmountLabel))
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
    }

    @ViewBuilder private var mark: some View {
        let ring = GoalRing(progress: progress, isBoolean: isBoolean)
        if let onMarkTap {
            Button(action: onMarkTap) {
                ring.tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(incrementLabel))
        } else {
            ring
        }
    }
}

/// Adds a VoiceOver action only when a value editor is available (boolean rows stay clean).
private struct GoalValueAccessibilityAction: ViewModifier {
    var action: (() -> Void)?
    var label: LocalizedStringKey

    @ViewBuilder func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: Text(label), action)
        } else {
            content
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

/// Calendar row: start time in the gutter; end cue on the secondary line.
struct InkCalendarRow: View {
    var time: String?
    let title: String
    var endLabel: String? = nil

    var body: some View {
        MarginRow(kind: .external, time: time) {
            Text(verbatim: title)
                .foregroundStyle(.ink.text)
        } secondary: {
            if let endLabel, !endLabel.isEmpty {
                Text(verbatim: endLabel)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
        }
    }
}
