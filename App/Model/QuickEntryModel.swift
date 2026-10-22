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
    var languages: [DateParsing.Language] = DateParsingLanguages.preferred(for: DateParsingLanguages.appLocale)
    /// Decides which day a week expression (`haftaya`, `next week`) means.
    var calendar = Calendar.autoupdatingCurrent
    var taskRecurrence: TaskRecurrence?
    var taskPriority: TaskPriority?
    var overridesDate = false
    var manualDueDate: CalendarDate?
    var manualDateIsAssumed = false
    /// Task expressions the user turned back into plain words, as UTF-8 ranges of `text`.
    var suppressedExpressions: [Range<Int>] = []
    /// Names the user turned back into plain words; the composer reads them, this model moves
    /// them with the text exactly as it moves `suppressedExpressions`.
    var suppressedNames: [Range<Int>] {
        get { composer.suppressed }
        set { composer.suppressed = newValue }
    }
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
    /// Set while the field holds a draft made from a calendar event.
    var calendarDraft: CalendarDraft?
    /// Set while lines from a journaling suggestion wait for the field (``applySuggestion(_:)``).
    var suggestionQueue: SuggestionQueue?
    @ObservationIgnored var analysisCache: (key: AnalysisKey, analysis: QuickEntryAnalysis)?
    /// Project names the `#project/` suggestions offer (``loadProjects()``); a reload keeps the
    /// previous names until it answers.
    var knownProjects: [String] = []

    var text: String {
        get { composer.text }
        set {
            let old = composer.text
            composer.text = newValue
            // The composer reports only unequal strings, and two spellings of one accented letter
            // compare equal; the suppressed byte ranges still have to follow the new bytes.
            if old == newValue, !old.utf8.elementsEqual(newValue.utf8) { reconcileRecognitions(oldText: old) }
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
        // Suggestions and "Vazgeç" edit the text through the composer, not through `text`.
        composer.onTextChange = { [weak self] old in self?.reconcileRecognitions(oldText: old) }
    }

    var isHistorical: Bool { day.map { $0 != today() } ?? false }
    var entryTime: LineClock? {
        guard mode == .event, includesTime else { return nil }
        // Another day's moment keeps its own time on any page.
        if !isHistorical || suggestionDay != nil, let time = calendarDraft?.time { return LocalDay.clock(at: time) }
        return isHistorical ? LocalDay.clock(at: selectedTime) : LocalDay.clock(at: now())
    }

    var canSubmit: Bool {
        store.canAddEvent && !isSubmitting && !isCreating && !submissionText.allSatisfy(\.isWhitespace)
    }

    var mentions: [Mention] { composer.mentions }

    /// A name recognized in plain typing that the user can undo, with the UTF-8 range of `text` it covers.
    struct NameRecognition: Identifiable, Equatable {
        let byteRange: Range<Int>
        let spelling: String
        /// Sending asks which entity is meant.
        let isAmbiguous: Bool
        let kind: KnownEntity.Kind?
        var id: Int { byteRange.lowerBound }
    }

    /// Names that will be linked or asked about. An `@` mention and a pinned choice (a suggestion,
    /// a calendar attendee, a nearby place) were the user's own request and get no chip.
    var recognizedNames: [NameRecognition] {
        let pinned = Set(pins.map(\.range))
        // A task's expression takes its words out on sending, a name among them too ("Cuma" the
        // person in "Cuma'ya"): that name has no chip until the expression's chip is undone.
        let consumed = taskAnalysis?.tokens.map(\.byteRange) ?? []
        return mentions.compactMap { mention in
            guard !mention.isExplicit, mention.isCertain || mention.isAmbiguous else { return nil }
            let range = composer.globalRange(mention.position)
            guard !pinned.contains(range), !consumed.contains(where: { $0.overlaps(range) }) else { return nil }
            return NameRecognition(
                byteRange: range, spelling: mention.spelling, isAmbiguous: mention.isAmbiguous,
                kind: mention.isCertain ? mention.candidates[0].kind : nil)
        }
    }

    /// Keeps this occurrence of the name as plain words: it is neither linked nor asked about.
    func undoRecognition(_ name: NameRecognition) {
        suppressedNames.append(name.byteRange)
    }

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
    @discardableResult
    func selectSuggestion(_ entity: KnownEntity, at byteOffset: Int? = nil) -> Int? {
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
        let draftCalendar = calendarDraftSnapshot
        let draft = text
        let draftPins = pins
        let draftSkipped = skipped
        let draftRecurrence = taskRecurrence
        let draftPriority = taskPriority
        let draftOverridesDate = overridesDate
        let draftManualDueDate = manualDueDate
        let draftManualDateIsAssumed = manualDateIsAssumed
        let draftSuppressed = suppressions
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
            suppressions = Suppressions()
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
                // Another day's moment goes to its own day's file (``suggestionDay``).
                let target = draftCalendar.draft?.suggestion?.day ?? day ?? LocalDay.today()
                saved = await store.addEvent(on: target, text: payload, time: time)
            }
            if !saved {
                restoreFailedDraft(
                    draft, pins: draftPins, skipped: draftSkipped, recurrence: draftRecurrence,
                    priority: draftPriority, overridesDate: draftOverridesDate,
                    manualDueDate: draftManualDueDate, manualDateIsAssumed: draftManualDateIsAssumed,
                    suppressed: draftSuppressed, dismissedLocation: draftDismissedLocation)
                composer.errorText =
                    store.entryErrorText
                    ?? String(localized: "Olay kaydedilemedi. Kasayı kontrol edip yeniden dene.")
                restoreCalendarDraft(draftCalendar)
            } else {
                advanceSuggestions(afterSending: submitMode == .event ? draftCalendar.draft?.suggestion : nil)
            }
            return saved
        } catch {
            isSubmitting = false
            restoreFailedDraft(
                draft, pins: draftPins, skipped: draftSkipped, recurrence: draftRecurrence,
                priority: draftPriority, overridesDate: draftOverridesDate,
                manualDueDate: draftManualDueDate, manualDateIsAssumed: draftManualDateIsAssumed,
                suppressed: draftSuppressed, dismissedLocation: draftDismissedLocation)
            composer.errorText = String(localized: "Anmalar bağlanamadı. Metni kontrol edip yeniden dene.")
            return false
        }
    }

    private func restoreFailedDraft(
        _ draft: String, pins draftPins: [Pin], skipped draftSkipped: Set<MentionPosition>,
        recurrence: TaskRecurrence?, priority: TaskPriority?, overridesDate: Bool,
        manualDueDate: CalendarDate?, manualDateIsAssumed: Bool, suppressed: Suppressions,
        dismissedLocation: Bool
    ) {
        if text.isEmpty {
            text = draft
            suppressions = suppressed
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
        // The failed entry is the prefix, so its ranges still point at the same bytes.
        suppressions = suppressed
        taskRecurrence = recurrence
        taskPriority = priority
        self.overridesDate = overridesDate
        self.manualDueDate = manualDueDate
        self.manualDateIsAssumed = manualDateIsAssumed
        self.dismissedLocation = dismissedLocation
    }

    private func reconcileRecognitions(oldText: String) {
        if text.isEmpty { clearCalendarDraft() }
        let suppressed = suppressedExpressions
        suppressions = suppressions.following(from: oldText, to: text)
        guard mode == .task else { return }
        // Both sides go through the analysis: a plain date parse of the old text takes the weekday of
        // `her salı` for a date and every keystroke would look like a changed date.
        if analysis(of: oldText, suppressing: suppressed).date?.date != dateExpression?.date {
            overridesDate = false
            manualDueDate = nil
            manualDateIsAssumed = false
        }
    }
}
