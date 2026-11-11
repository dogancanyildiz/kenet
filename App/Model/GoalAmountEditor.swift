import Foundation
import GoalTracking
import Observation
import VaultFormat

/// The goal page's amount for one day of a number goal, as text the person types: what the field
/// shows, when a commit writes and what it writes. Writes go through the day's ``GoalDayModel``.
///
/// A commit writes only text the person changed: a value shown and left alone is never written
/// back, whatever its precision. A write that meets a reload or another write waits for it; a
/// write that fails keeps the typed text and says why.
/// A write that failed after its panel went away (back, another day): nobody sees that panel's
/// band, so the goal page and Today's goal strip show it until it is closed or a later write
/// succeeds.
@MainActor @Observable
final class GoalAmountNotice {
    static let shared = GoalAmountNotice()
    var message: String?
}

@MainActor @Observable
final class GoalAmountEditor {
    let dayModel: GoalDayModel
    /// The goal as the panel was opened with it; ``goal`` is its newest definition.
    private let openedGoal: GoalDefinition
    /// The goal's newest definition in the day model (an edit of the goal's name or target
    /// reloads it); writes need it, since the day model takes only a definition it lists.
    var goal: GoalDefinition { dayModel.goals.first { $0.id == openedGoal.id } ?? openedGoal }
    /// The panel went away: a failure is reported through ``GoalAmountNotice``.
    @ObservationIgnored var isDetached = false
    /// How numbers are shown and read ("7.500" is 7500 in Turkish).
    var locale: Locale {
        didSet { refresh() }
    }
    /// The field's text.
    var text: String
    /// The text the field showed for the saved value; a commit with the same text writes nothing.
    private(set) var shownText: String
    private(set) var errorText: String?
    private(set) var isCommitting = false
    /// How long a commit waits for a reload or another write to end before it gives up.
    @ObservationIgnored var transientWait: Duration = .seconds(10)

    init(dayModel: GoalDayModel, goal: GoalDefinition, locale: Locale = .current) {
        self.dayModel = dayModel
        openedGoal = goal
        self.locale = locale
        let shown = Self.display(Self.amount(in: dayModel, goal: goal), locale: locale)
        text = shown
        shownText = shown
    }

    /// The day's saved amount; 0 without a record.
    var dayValue: Double { Self.amount(in: dayModel, goal: goal) }
    var hasRecord: Bool { dayModel.value(for: goal) != nil }
    /// The person changed the field since it last showed the saved value.
    var isDirty: Bool { text != shownText }
    /// The changed text does not read as an amount (the field's hint).
    var isInvalid: Bool {
        isDirty && !text.trimmingCharacters(in: .whitespaces).isEmpty
            && GoalValueModel.number(text, locale: locale) == nil
    }

    /// Nothing can be typed: no vault or a read-only one, or the day not loaded yet. A reload or a
    /// write in flight does not lock the field; a commit waits for it instead.
    var isLocked: Bool {
        !dayModel.belongs(to: dayModel.store.vaultURL) || dayModel.store.vaultURL == nil
            || !dayModel.store.canAddEvent || !dayModel.hasLoaded
    }

    /// The amount quick steps and "Hedefe tamamla" start from: the typed value while the field
    /// holds a change that reads, the saved value otherwise (also after a failed write).
    var baseValue: Double {
        guard isDirty, errorText == nil, let typed = GoalValueModel.number(text, locale: locale) else {
            return dayValue
        }
        return typed
    }

    /// The period's total over all its days, also those after this day (a past Monday of a week
    /// with a Wednesday record counts the Wednesday).
    var periodTotal: Double {
        let end = goal.period == .day ? dayModel.day : dayModel.status(for: goal).periodEnd
        return GoalProgress.compute(definition: goal, logs: dayModel.logs[goal.key] ?? [], today: end)
            .progress.done
    }

    /// The day's amount that brings the whole period to its target; nil once it is met.
    var completionValue: Double? {
        GoalAmountPresentation.completionValue(
            dayValue: baseValue, periodDone: periodTotal - dayValue + baseValue, target: goal.target)
    }

    /// The saved value changed (a write here or a reload): the field follows it unless it holds
    /// a change of the person's.
    func refresh() {
        let shown = Self.display(dayValue, locale: locale)
        if !isDirty { text = shown }
        shownText = shown
        if text == shownText { errorText = nil }
    }

    /// Writes the typed amount when the person changed it. Empty text goes back to the saved
    /// value (removing is "Kaydı kaldır"). Text typed while a write runs is written right after
    /// it, by the commit already running. True when nothing is left to write.
    @discardableResult
    func commit() async -> Bool {
        // The running commit picks up what was typed meanwhile (its loop below).
        guard !isCommitting else { return true }
        var rounds = 0
        while isDirty, rounds < 5 {
            rounds += 1
            let typed = text
            if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = shownText
                errorText = nil
                return true
            }
            guard let value = GoalValueModel.number(typed, locale: locale) else { return false }
            // The same amount written another way ("7.500" for 7500): nothing to write.
            if value == dayValue, hasRecord || value == 0 {
                if text == typed { text = shownText }
                errorText = nil
                continue
            }
            guard await write(.number(value), typed: typed) else { return false }
        }
        return !isDirty
    }

    /// Takes back what was typed and not written (the goal is being deleted).
    func discard() {
        text = shownText
        errorText = nil
    }

    /// A quick step or "Hedefe tamamla": shown in the field and written at once.
    @discardableResult
    func apply(_ value: Double) async -> Bool {
        text = Self.display(value, locale: locale)
        return await commit()
    }

    @discardableResult
    func add(_ step: Double) async -> Bool { await apply(baseValue + step) }

    @discardableResult
    func completeTarget() async -> Bool {
        guard let completionValue else { return false }
        return await apply(completionValue)
    }

    /// Removes the day's record of this goal (after the page's confirmation).
    @discardableResult
    func remove() async -> Bool {
        guard hasRecord, !isCommitting else { return !hasRecord }
        return await write(nil, typed: text)
    }

    /// One write of `value`, made for the field text `typed`. Text typed since stays in the field
    /// (the commit loop writes it next).
    private func write(_ value: GoalValue?, typed: String) async -> Bool {
        isCommitting = true
        defer { isCommitting = false }
        let before = dayModel.value(for: goal)
        let waited = await waitForTransientWork()
        // The day changed while this write waited (another page wrote it, an outside edit): this
        // older write would overwrite the newer value, so it stops and says so.
        if waited, dayModel.value(for: goal) != before {
            fail(
                String(
                    localized: "Bu günün değeri bu arada değişti; yazdığın değer kaydedilmedi.",
                    bundle: PresentationLocalization.bundle(locale), locale: locale))
            return false
        }
        let written = await dayModel.set(goal, value: value)
        if written {
            shownText = Self.display(dayValue, locale: locale)
            if text == typed { text = shownText }
            errorText = dayModel.errorText
            if errorText == nil { GoalAmountNotice.shared.message = nil }
        } else {
            fail(
                dayModel.errorText
                    ?? String(
                        localized: "Değer kaydedilemedi; yeniden dene.",
                        bundle: PresentationLocalization.bundle(locale), locale: locale))
        }
        return written
    }

    private func fail(_ message: String) {
        errorText = message
        if isDetached { GoalAmountNotice.shared.message = "\(goal.name): \(message)" }
    }

    /// A reload (an outside change published) or another write in flight: wait for it rather than
    /// let the write fail. A lock that stays (read-only vault) does not wait.
    /// True when it had to wait.
    private func waitForTransientWork() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: transientWait)
        var waited = false
        while !dayModel.canEdit, dayModel.isLoading || dayModel.isWriting || !dayModel.hasLoaded,
            dayModel.store.canAddEvent, dayModel.belongs(to: dayModel.store.vaultURL), clock.now < deadline
        {
            waited = true
            try? await Task.sleep(for: .milliseconds(50))
        }
        return waited
    }

    private static func amount(in model: GoalDayModel, goal: GoalDefinition) -> Double {
        if case .number(let number) = model.value(for: goal) { number } else { 0 }
    }

    /// Lossless and in ASCII digits: a whole amount without a mark, else the shortest decimal
    /// that reads back as the same value, with `locale`'s decimal mark ("1,23456789" in Turkish).
    nonisolated static func display(_ value: Double, locale: Locale) -> String {
        let value = value == 0 ? 0 : value
        if value == value.rounded(), abs(value) < 9e18 { return String(Int64(value)) }
        let decimal = locale.decimalSeparator == "," ? "," : "."
        var plain = String(value)
        if plain.contains("e") {
            // Exponent notation (very small or large): spell it out, still exact enough to read back.
            plain = value.formatted(
                .number.grouping(.never).precision(.fractionLength(0...17)).locale(Locale(identifier: "en_US_POSIX")))
        }
        return plain.replacingOccurrences(of: ".", with: decimal)
    }
}
