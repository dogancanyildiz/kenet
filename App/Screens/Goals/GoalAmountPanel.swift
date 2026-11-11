import GoalTracking
import SwiftUI
import VaultFormat

/// The amount rules of a number goal (unit-tested): when the card's "+" adds one, which quick
/// steps the goal page offers and what "Hedefe tamamla" writes.
enum GoalAmountPresentation {
    /// Up to this target the card's "+" adds one (8 glasses); above it (7500 steps) the card shows
    /// a pencil that opens the goal page with the amount field focused.
    static let quickIncrementLimit: Double = 20

    /// True when the card's trailing control adds one: every yes/no goal, and a number goal up to
    /// ``quickIncrementLimit``.
    static func usesQuickIncrement(_ goal: GoalDefinition) -> Bool {
        goal.kind != .number || goal.target <= quickIncrementLimit
    }

    /// The page's quick-add steps: about a fifteenth, a seventh and a third of the target, each
    /// rounded down to 1, 2, 2.5 or 5 times a power of ten, whole, at least 1, without repeats.
    /// 7500 → 500, 1000, 2500; 20 → 1, 2, 5; 8 → 1, 2.
    static func quickSteps(target: Double) -> [Double] {
        guard target.isFinite, target > 0 else { return [1] }
        var steps: [Double] = []
        for share in [target / 15, target / 7.5, target / 3] {
            let step = niceFloor(share)
            if !steps.contains(step) { steps.append(step) }
        }
        return steps
    }

    /// `value` rounded down to the nearest 1, 2, 2.5 or 5 × 10ⁿ; 2.5 only where it is whole.
    static func niceFloor(_ value: Double) -> Double {
        guard value.isFinite, value > 1 else { return 1 }
        var magnitude = pow(10, floor(log10(value)))
        // log10 of an exact power of ten can land just under the whole number.
        if value / magnitude >= 10 - 1e-9 { magnitude *= 10 }
        let mantissa = value / magnitude + 1e-9
        let nice: Double =
            if mantissa >= 5 { 5 } else if mantissa >= 2.5 { 2.5 } else if mantissa >= 2 { 2 } else { 1 }
        let step = nice * magnitude
        return step == step.rounded() ? step : 2 * magnitude
    }

    /// The day's amount that completes the period's target: the day's value plus what the period
    /// still lacks. Nil once the period reached its target.
    static func completionValue(dayValue: Double, periodDone: Double, target: Double) -> Double? {
        let missing = target - periodDone
        guard missing > 0 else { return nil }
        return dayValue + missing
    }
}

/// A number goal's amount for one day, typed in place: the large number takes the keyboard
/// (a number pad on iPhone), quick-add steps and "Hedefe tamamla" sit under it, and a small
/// "Kaydı kaldır" removes the day's record after a confirmation. Writes go through
/// ``GoalValueModel`` and the day's ``GoalDayModel``, as the former amount sheet did.
struct GoalAmountPanel: View {
    let model: GoalDayModel
    let goal: GoalDefinition
    /// Close Day's row: no ring and no period line, a smaller number.
    var isCompact = false
    /// Each change above zero focuses the amount field (a pencil, a heatmap day, a log row).
    var focusToken = 0
    /// Runs after a write that succeeded (the page reloads its history for a past day).
    var onWrite: (() async -> Void)? = nil

    @Environment(\.locale) private var locale
    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var removal = DestructiveConfirmation<DestructiveConfirmationToken>()
    @ScaledMetric(relativeTo: .largeTitle) private var largeSide = InkSize.largeNumber
    @ScaledMetric(relativeTo: .title2) private var compactSide: CGFloat = 28

    private var dayValue: Double {
        if case .number(let number) = model.value(for: goal) { number } else { 0 }
    }

    private var hasRecord: Bool { model.value(for: goal) != nil }
    private var canRemove: Bool { model.canEdit && hasRecord }
    private var typedValue: Double? { GoalValueModel.number(text) }

    var body: some View {
        let status = model.status(for: goal)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    amountLine
                    if !isCompact, let line = periodLine(status: status) {
                        Text(verbatim: line)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if typedValue == nil {
                        Text("Sıfır veya pozitif bir sayı gir.")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !isCompact {
                    Spacer(minLength: 0)
                    GoalRing(
                        progress: status.progress.fraction,
                        isBoolean: false,
                        diameter: 64,
                        centerLabel: status.progress.isComplete
                            ? "✓"
                            : GoalListPresentation.percentLabel(
                                done: status.progress.done, target: goal.target, locale: locale)
                    )
                    .accessibilityHidden(true)
                }
            }
            quickButtons(status: status)
            // A small link, not a button row: removing is rare and asks first.
            Button(role: .destructive) {
                removal.request(.pending)
            } label: {
                Text("Kaydı kaldır")
                    .font(.ink.meta)
                    .foregroundStyle(canRemove ? Color.ink.danger : Color.ink.tertiaryText)
                    .frame(minHeight: TapTarget.minimumLength)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRemove)
            .accessibilityIdentifier("button.goal.amount.remove")
        }
        .onChange(of: dayValue, initial: true) { _, _ in
            if !focused { text = display(dayValue) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { Task { await commit() } }
        }
        .task(id: focusToken) {
            guard focusToken > 0 else { return }
            // After the page's push: a field focused mid-transition loses the keyboard.
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
        .destructiveConfirmationDialog(
            "Kaydı kaldır?", confirmation: $removal, confirmTitle: "Kaydı kaldır"
        ) { _ in
            Task { await remove() }
        }
    }

    /// "7500 / 7500 adım": the day's amount is the field, the target and unit follow it.
    private var amountLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            amountField
            Text(verbatim: "/ " + goal.target.formatted(.number.locale(locale)))
                .font(.ink.value)
                .foregroundStyle(Color.ink.secondaryText)
                .fixedSize()
            if let unit = goal.unit {
                Text(verbatim: unit)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .lineLimit(1)
            }
            if focused {
                Button {
                    focused = false
                } label: {
                    Label("Kaydet", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.ink.meta.weight(.semibold))
                        .foregroundStyle(Color.ink.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.ink.accent))
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button.goal.amount.save")
            }
        }
    }

    private var amountFont: Font {
        .system(size: isCompact ? compactSide : largeSide, weight: .bold).monospacedDigit()
    }

    /// As wide as the typed number (plus one digit of room), not the placeholder's width.
    private var amountField: some View {
        Text(verbatim: (text.isEmpty ? "0" : text) + "0")
            .font(amountFont)
            .lineLimit(1)
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                TextField("Miktar", text: $text)
                    .textFieldStyle(.plain)
                    .font(amountFont)
                    .foregroundStyle(Color.ink.text)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    .focused($focused)
                    .onSubmit { focused = false }
                    .accessibilityLabel(Text("Miktar"))
                    .accessibilityIdentifier("field.goal.amount")
            }
            .frame(minWidth: TapTarget.minimumLength, minHeight: TapTarget.minimumLength, alignment: .leading)
            .padding(.horizontal, 10)
            .background(
                Color.ink.well,
                in: RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                    .strokeBorder(
                        InkButtonChrome.color(for: InkFilterFieldChrome.borderToken(isFocused: focused)),
                        lineWidth: InkStroke.control)
            )
            .disabled(!model.canEdit)
    }

    /// "+500 +1000 +2500" and "Hedefe tamamla", wrapping on narrow widths and large text.
    private func quickButtons(status: GoalStatus) -> some View {
        let completion = GoalAmountPresentation.completionValue(
            dayValue: dayValue, periodDone: status.progress.done, target: goal.target)
        return InkFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(GoalAmountPresentation.quickSteps(target: goal.target), id: \.self) { step in
                let amount = step.formatted(.number.locale(locale))
                Button {
                    apply((typedValue ?? dayValue) + step)
                } label: {
                    Text(verbatim: "+" + amount).monospacedDigit()
                }
                .buttonStyle(GoalAmountButtonStyle())
                .accessibilityLabel(Text("\(amount) ekle"))
            }
            Button {
                if let completion { apply(completion) }
            } label: {
                Text("Hedefe tamamla")
            }
            .buttonStyle(GoalAmountButtonStyle())
            .disabled(completion == nil)
            .accessibilityIdentifier("button.goal.amount.complete")
        }
        .disabled(!model.canEdit)
    }

    /// "Bu hafta 12/50 km" for a weekly or yearly goal; "2500 kaldı" for a daily one.
    private func periodLine(status: GoalStatus) -> String? {
        if goal.period == .day {
            return GoalListPresentation.remainingText(goal: goal, status: status, locale: locale)
        }
        let key: String.LocalizationValue = goal.period == .week ? "Bu hafta" : "Bu yıl"
        let period = String(localized: key, bundle: PresentationLocalization.bundle(locale), locale: locale)
        let amount =
            status.progress.done.formatted(.number.locale(locale)) + "/"
            + goal.target.formatted(.number.locale(locale))
        return [period, amount, goal.unit].compactMap { $0 }.joined(separator: " ")
    }

    private func display(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).locale(locale))
    }

    /// A quick step or the completion: written at once, or through the field's commit while it
    /// holds the keyboard, so one tap gives one write.
    private func apply(_ value: Double) {
        text = display(value)
        if focused { focused = false } else { Task { await commit() } }
    }

    private func commit() async {
        guard let value = typedValue else { return }
        // Nothing changed: no write (an empty day stays without a record at zero).
        if value == dayValue, hasRecord || value == 0 {
            text = display(dayValue)
            return
        }
        let editor = GoalValueModel(dayModel: model, goal: goal)
        editor.amount = String(value)
        if await editor.save() {
            text = display(dayValue)
            await onWrite?()
        }
    }

    private func remove() async {
        let editor = GoalValueModel(dayModel: model, goal: goal)
        if await editor.save(remove: true) {
            text = display(0)
            await onWrite?()
        }
    }
}
