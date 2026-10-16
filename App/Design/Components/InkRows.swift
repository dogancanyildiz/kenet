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
                .accessibilityHidden(true)
            Text(verbatim: text)
        }
        .font(.ink.meta)
        .foregroundStyle(.ink.warning)
        .accessibilityLabel(Text("Devreden"))
        .accessibilityValue(Text(verbatim: text))
    }
}

/// Goal row: ring, name, optional streak/series meta, trailing value + one-tap plus.
/// With ``onOpen`` the name and meta open the goal's page; plus, value and ring keep their own taps.
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
    /// Opens the goal's page from the name and meta.
    var onOpen: (() -> Void)? = nil
    var showsPlus: Bool = true
    /// False while a write or a reload runs: plus, value and ring stay in place but take no taps.
    var isEditable: Bool = true
    /// One layout whatever the row's state: the plus slot stays, empty, when no plus is drawn (a
    /// marked yes/no goal), and a tappable ring stays at the top of its tap area.
    var keepsLayout: Bool = false
    var incrementLabel: LocalizedStringKey = "Artır"
    var enterAmountLabel: LocalizedStringKey = "Miktar gir"
    var openHint: LocalizedStringKey = "Ayrıntıları göster"

    @ScaledMetric(relativeTo: .body) private var plusSide = InkSize.plus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            goalRow
            if let barFraction {
                InkProgress(kind: .fraction(barFraction))
                    .padding(.leading, InkSpacing.gutter + 10)
            }
        }
        // The action stays while the row cannot edit (no change of identity); it then does nothing.
        .modifier(
            GoalValueAccessibilityAction(
                action: onValueTap.map { tap in { if isEditable { tap() } } }, label: enterAmountLabel))
    }

    private var hasPlusSlot: Bool { (showsPlus && onIncrement != nil) || keepsLayout }

    private var metaText: String? { meta.flatMap { $0.isEmpty ? nil : $0 } }

    private var nameText: some View {
        Text(verbatim: name)
            .foregroundStyle(progress >= 1 ? Color.ink.secondaryText : Color.ink.text)
    }

    private func metaLine(_ meta: String) -> some View {
        Text(verbatim: meta)
            .font(.ink.meta)
            .foregroundStyle(.ink.secondaryText)
    }

    /// Name and meta as one button: the same 4 pt stack ``MarginRow`` draws them in.
    private func openButton(_ onOpen: @escaping () -> Void) -> some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                nameText
                if let metaText { metaLine(metaText) }
            }
            // Tap area as tall as the value button's and the plus slot's, the text on top.
            .frame(
                maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .topLeading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: valueText ?? metaText ?? ""))
        .accessibilityHint(Text(openHint))
    }

    private var goalRow: some View {
        MarginRow(kind: .vault) {
            mark
        } primary: {
            if let onOpen {
                openButton(onOpen)
            } else {
                nameText
            }
        } secondary: {
            if onOpen == nil, let metaText {
                metaLine(metaText)
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
                        .disabled(!isEditable)
                        // With the name button beside it, the name is read once.
                        .accessibilityLabel(Text(verbatim: onOpen == nil ? name : valueText))
                        .accessibilityValue(Text(verbatim: onOpen == nil ? valueText : ""))
                        .accessibilityHint(Text(enterAmountLabel))
                    } else {
                        Text(verbatim: valueText)
                            .font(.ink.value)
                            .foregroundStyle(.ink.secondaryText)
                    }
                } else if InkGoalRowTrailing.needsValueBaselinePlaceholder(showsPlus: hasPlusSlot) {
                    // Same `.ink.value` baseline as valued rows so the name does not drop ~5 pt.
                    Text(verbatim: " ")
                        .font(.ink.value)
                        // Same top-aligned box as a tappable value, or the row centers it
                        // beside the 44 pt plus button and the baseline drops.
                        .frame(minHeight: TapTarget.minimumLength, alignment: .top)
                        .accessibilityHidden(true)
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
                            .opacity(isEditable ? 1 : InkGoalRowTrailing.busyPlusOpacity)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEditable)
                    .accessibilityLabel(Text(incrementLabel))
                } else if keepsLayout {
                    Color.clear
                        .frame(width: plusSide, height: plusSide)
                        .frame(
                            minWidth: TapTarget.minimumLength,
                            minHeight: TapTarget.minimumLength, alignment: .top
                        )
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder private var mark: some View {
        let ring = GoalRing(progress: progress, isBoolean: isBoolean)
        if let onMarkTap {
            Button(action: onMarkTap) {
                if keepsLayout {
                    ring.topAlignedTapTarget()
                } else {
                    ring.tapTarget()
                }
            }
            .buttonStyle(.plain)
            .disabled(!isEditable)
            .accessibilityLabel(Text(incrementLabel))
        } else {
            ring
        }
    }
}

extension GoalRing {
    /// The tap area grows down and out, as the plus button's: the ring stays where an untappable
    /// ring is drawn.
    fileprivate func topAlignedTapTarget() -> some View {
        #if os(iOS)
            frame(
                minWidth: TapTarget.minimumLength, minHeight: TapTarget.minimumLength, alignment: .top
            )
            .contentShape(Rectangle())
        #else
            self
        #endif
    }
}

/// Trailing-slot layout for ``InkGoalRow`` (unit-tested).
enum InkGoalRowTrailing {
    /// When there is no value text, a hidden `.ink.value` placeholder keeps the name on the same
    /// baseline as valued rows (MarginRow aligns trailing on ``firstTextBaseline``).
    static func needsValueBaselinePlaceholder(showsPlus: Bool) -> Bool {
        showsPlus
    }

    /// The plus while the row cannot edit: in place, faded.
    static let busyPlusOpacity = 0.4
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
