import DateParsing
import EntityRecognition
import Foundation
import Observation
import VaultFormat
import VaultStore

@MainActor @Observable
final class QuickEntryModel {
    typealias CreationRequest = MentionComposer.CreationRequest
    typealias Pin = MentionComposer.Pin

    enum Mode { case event, task }
    var mode = Mode.event {
        didSet {
            composer.awaitingResolution = false
            taskRecurrence = nil
            taskPriority = nil
            overridesDate = false
            manualDueDate = nil
            manualDateIsAssumed = false
        }
    }
    var languages: [DateParsing.Language] =
        (Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first)?.hasPrefix("tr") == true
        ? [.turkish, .english] : [.english, .turkish]
    var taskRecurrence: TaskRecurrence?
    var taskPriority: TaskPriority?
    var overridesDate = false
    var manualDueDate: CalendarDate?
    var manualDateIsAssumed = false
    let today: () -> CalendarDate
    let now: () -> Date

    var locationService: LocationService?
    var dismissedLocation = false
    let store: IndexStore
    let day: CalendarDate?
    var selectedTime: Date
    let composer: MentionComposer
    var includesTime = true
    private(set) var isSubmitting = false

    var text: String {
        get { composer.text }
        set {
            let old = composer.text
            composer.text = newValue
            reconcileTaskDate(oldText: old)
        }
    }
    var qualifier: String {
        get { composer.qualifier }
        set { composer.qualifier = newValue }
    }
    var needsQualifier: Bool {
        get { composer.needsQualifier }
        set { composer.needsQualifier = newValue }
    }
    var creationKind: VaultEntityKind? {
        get { composer.creationKind }
        set { composer.creationKind = newValue }
    }
    var errorText: String? {
        get { composer.errorText }
        set { composer.errorText = newValue }
    }
    var isCreating: Bool { composer.isCreating }
    var awaitingResolution: Bool {
        get { composer.awaitingResolution }
        set { composer.awaitingResolution = newValue }
    }
    var requestedCreation: CreationRequest? {
        get { composer.requestedCreation }
        set { composer.requestedCreation = newValue }
    }
    var pins: [Pin] {
        get { composer.pins }
        set { composer.pins = newValue }
    }
    var skipped: Set<MentionPosition> {
        get { composer.skipped }
        set { composer.skipped = newValue }
    }

    init(
        store: IndexStore, day: CalendarDate? = nil,
        today: @escaping () -> CalendarDate = { LocalDay.today() },
        now: @escaping () -> Date = { Date() }
    ) {
        self.today = today
        self.now = now
        self.store = store
        self.day = day
        self.composer = MentionComposer(store: store)
        self.selectedTime = now()
        includesTime = day == nil || day == today()
    }

    var isHistorical: Bool { day.map { $0 != today() } ?? false }
    var entryTime: LineClock? {
        guard mode == .event, includesTime else { return nil }
        return isHistorical ? LocalDay.clock(at: selectedTime) : LocalDay.clock(at: now())
    }

    var canSubmit: Bool {
        store.canAddEvent && !isSubmitting && !isCreating && !submissionText.allSatisfy(\.isWhitespace)
    }

    var mentions: [Mention] { composer.mentions }
    var choices: [MentionPosition: String] { composer.choices }
    var pendingAmbiguity: Mention? { composer.pendingAmbiguity }
    var pendingUnknown: CreationRequest? { composer.pendingUnknown }

    func choose(_ entity: KnownEntity, for mention: Mention) { composer.choose(entity, for: mention) }
    func skip(_ mention: Mention) { composer.skip(mention) }
    func dismissUnknown(_ mention: CreationRequest) { composer.dismissUnknown(mention) }
    func create(_ kind: VaultEntityKind) async { await composer.create(kind) }
    func suggestionRange(at byteOffset: Int? = nil) -> Range<Int>? {
        composer.suggestionRange(at: byteOffset)
    }
    func suggestions(at byteOffset: Int? = nil) -> [KnownEntity] {
        composer.suggestions(at: byteOffset)
    }
    func beginCreation(_ kind: VaultEntityKind, at byteOffset: Int? = nil) async {
        await composer.beginCreation(kind, at: byteOffset)
    }
    func selectSuggestion(_ entity: KnownEntity, at byteOffset: Int? = nil) {
        composer.selectSuggestion(entity, at: byteOffset)
    }
    func globalRange(_ position: MentionPosition) -> Range<Int> { composer.globalRange(position) }
    func replace(_ range: Range<Int>, with replacement: String) {
        composer.replace(range, with: replacement)
    }

    @discardableResult
    func submit(time: LineClock?) async -> Bool {
        guard canSubmit else { return false }
        locationService?.requestLocationIfNeeded()
        if mode == .task { prepareTaskText() }
        guard composer.beginResolution() else { return false }
        isSubmitting = true
        errorText = nil
        let draft = text
        let draftPins = pins
        let draftSkipped = skipped
        let draftRecurrence = taskRecurrence
        let draftPriority = taskPriority
        let draftOverridesDate = overridesDate
        let draftManualDueDate = manualDueDate
        let draftManualDateIsAssumed = manualDateIsAssumed
        let draftDismissedLocation = dismissedLocation
        let submitMode = mode
        let submitDue = dueDate
        let submitPriority = taskPriority
        let submitRecurrence = taskRecurrence
        do {
            let payload = try composer.linkedText()
            // Clear immediately so a second Enter can queue while this write runs.
            dismissedLocation = false
            text = ""
            taskRecurrence = nil
            taskPriority = nil
            overridesDate = false
            manualDueDate = nil
            manualDateIsAssumed = false
            pins = []
            skipped = []
            awaitingResolution = false
            isSubmitting = false
            let saved: Bool
            if submitMode == .task {
                saved = await store.addTask(
                    on: today(), text: payload, due: submitDue, priority: submitPriority,
                    recurrence: submitRecurrence)
            } else {
                saved = await store.addEvent(on: day ?? LocalDay.today(), text: payload, time: time)
            }
            if !saved {
                restoreFailedDraft(
                    draft, pins: draftPins, skipped: draftSkipped, recurrence: draftRecurrence,
                    priority: draftPriority, overridesDate: draftOverridesDate,
                    manualDueDate: draftManualDueDate, manualDateIsAssumed: draftManualDateIsAssumed,
                    dismissedLocation: draftDismissedLocation)
                composer.errorText =
                    store.entryErrorText
                    ?? String(localized: "Olay kaydedilemedi. Kasayı kontrol edip yeniden dene.")
            }
            return saved
        } catch {
            isSubmitting = false
            restoreFailedDraft(
                draft, pins: draftPins, skipped: draftSkipped, recurrence: draftRecurrence,
                priority: draftPriority, overridesDate: draftOverridesDate,
                manualDueDate: draftManualDueDate, manualDateIsAssumed: draftManualDateIsAssumed,
                dismissedLocation: draftDismissedLocation)
            composer.errorText = String(localized: "Anmalar bağlanamadı. Metni kontrol edip yeniden dene.")
            return false
        }
    }

    private func restoreFailedDraft(
        _ draft: String, pins draftPins: [Pin], skipped draftSkipped: Set<MentionPosition>,
        recurrence: TaskRecurrence?, priority: TaskPriority?, overridesDate: Bool,
        manualDueDate: CalendarDate?, manualDateIsAssumed: Bool, dismissedLocation: Bool
    ) {
        if text.isEmpty {
            text = draft
            pins = draftPins
            skipped = draftSkipped
            taskRecurrence = recurrence
            taskPriority = priority
            self.overridesDate = overridesDate
            self.manualDueDate = manualDueDate
            self.manualDateIsAssumed = manualDateIsAssumed
            self.dismissedLocation = dismissedLocation
            return
        }
        // Keep both the failed entry and whatever the user typed meanwhile.
        let typed = text
        pins = []
        skipped = []
        text = draft + "\n" + typed
        taskRecurrence = recurrence
        taskPriority = priority
        self.overridesDate = overridesDate
        self.manualDueDate = manualDueDate
        self.manualDateIsAssumed = manualDateIsAssumed
        self.dismissedLocation = dismissedLocation
    }

    private func reconcileTaskDate(oldText: String) {
        guard mode == .task else { return }
        let previous = DateExpressionParser.parse(oldText, today: today(), language: languages)?.date
        if previous != dateExpression?.date {
            overridesDate = false
            manualDueDate = nil
            manualDateIsAssumed = false
        }
    }
}
