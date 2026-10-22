import EntityRecognition
import Foundation
import VaultFormat
import VaultStore

extension QuickEntryModel {
    /// The lines of a picked suggestion that have not reached the field yet, and how many of its
    /// photos and videos were left out.
    struct SuggestionQueue: Equatable {
        var remaining: [SuggestionLine]
        var skippedMedia: Int
    }

    /// Fills the empty field with the pick's first line; the user still sends it. Each further
    /// line waits and enters the field after the previous one is sent. A draft already in the
    /// field is never replaced: the pick is refused and the field says why.
    @discardableResult
    func applySuggestion(
        _ pick: SuggestionPick, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> Bool {
        guard text.allSatisfy(\.isWhitespace) else {
            composer.errorText = String(localized: "Kutuda yazılmış bir taslak var. Önce onu gönder ya da sil.")
            return false
        }
        let draft = SuggestionText.draft(from: pick, locale: locale)
        guard !draft.lines.isEmpty || draft.skippedMedia > 0 else {
            suggestionQueue = nil
            return false
        }
        suggestionQueue = SuggestionQueue(remaining: draft.lines, skippedMedia: draft.skippedMedia)
        return takeNextSuggestion(timeZone: timeZone)
    }

    /// Moves the next waiting line into the empty field; a typed draft is never replaced.
    @discardableResult
    func takeNextSuggestion(timeZone: TimeZone = .current) -> Bool {
        guard var queue = suggestionQueue, !queue.remaining.isEmpty, text.allSatisfy(\.isWhitespace),
            !isSubmitting, !isCreating
        else { return false }
        let line = queue.remaining.removeFirst()
        suggestionQueue = queue
        fill(line, timeZone: timeZone)
        return true
    }

    /// After a saved entry (``submit(time:)``). Only a sent suggestion line brings the next one
    /// into the field, unsent; an entry the user wrote leaves the waiting lines and the mode alone.
    /// A queue with no lines left (its photo note) ends with any saved entry.
    func advanceSuggestions(afterSending sent: SuggestionFill?) {
        guard let queue = suggestionQueue else { return }
        if queue.remaining.isEmpty {
            suggestionQueue = nil
        } else if sent != nil {
            takeNextSuggestion()
        }
    }

    /// The waiting lines and the photo note go; the field keeps what it holds.
    func dropSuggestions() { suggestionQueue = nil }

    /// The day another day's moment is written to; nil writes to the page's day.
    var suggestionDay: CalendarDate? { mode == .event ? calendarDraft?.suggestion?.day : nil }

    /// Names of the line in the field that wait beside it as chips; a chip whose name is now in the
    /// text, pinned, is gone.
    var suggestedNames: [SuggestionLine.Mention] {
        guard mode == .event, let names = calendarDraft?.suggestion?.names else { return [] }
        return names.filter { name in
            let key = nameComparisonFold(name.name)
            return !pins.contains { $0.entity.kind == name.kind && $0.entity.comparisonKeys.contains(key) }
        }
    }

    /// A chip's name enters the text only as a pinned mention: one the vault now knows by the
    /// chip's kind at once, any other only after its entity is created (``MentionComposer``'s
    /// creation flow, which asks for a qualifier when the name is taken).
    func addSuggestedName(_ name: SuggestionLine.Mention) async {
        guard !isSubmitting, !isCreating else { return }
        if let certain = Self.certainMatch(name, among: store.knownEntities) {
            composer.appendPinned(certain.entity, spelling: certain.spelling)
            return
        }
        let kind: VaultEntityKind =
            switch name.kind {
            case .person: .person
            case .place: .place
            case .custom(let id): .custom(id)
            }
        await composer.beginCreation(kind, outsideTextNamed: name.name)
    }

    /// The only entity of the name's own kind that answers to the whole name; a person never
    /// matches a place.
    private static func certainMatch(
        _ name: SuggestionLine.Mention, among entities: [KnownEntity]
    ) -> AttendeeMatch.Certain? {
        let candidates = entities.filter { $0.kind == name.kind }
        return AttendeeMatching.match([Attendee(name: name.name)], entities: candidates).certain.first
    }

    /// A name with one entity of its own kind enters the text pinned; an ambiguous one enters as
    /// `@Name`, which sending asks about (as for calendar attendees). Any other name, also one
    /// that only an entity of another kind answers to, waits beside the text as a chip and never
    /// enters it unasked: the recognizer would link it to whatever answers to its first words.
    /// A moment of another day sends the line to that day's file at its own time.
    private func fill(_ line: SuggestionLine, timeZone: TimeZone) {
        var draft = line.text
        var pinned: [(entity: KnownEntity, range: Range<Int>)] = []
        var waiting: [SuggestionLine.Mention] = []
        func append(_ spelling: String) -> Range<Int> {
            if !draft.isEmpty { draft += " " }
            let start = draft.utf8.count + 1
            draft += "@" + spelling
            return start..<draft.utf8.count
        }
        for mention in line.mentions {
            let candidates = store.knownEntities.filter { $0.kind == mention.kind }
            let match = AttendeeMatching.match([Attendee(name: mention.name)], entities: candidates)
            if let certain = match.certain.first {
                pinned.append((certain.entity, append(certain.spelling)))
            } else if let ambiguous = match.ambiguous.first {
                _ = append(ambiguous.spelling)
            } else {
                waiting.append(mention)
            }
        }
        // A closing blank ends the mention, so the suggestion list stays shut.
        if waiting.count < line.mentions.count { draft += " " }
        mode = .event
        text = draft
        for pin in pinned { composer.pin(pin.entity, nameRange: pin.range) }
        let pageDay = day ?? today()
        let momentDay = line.start.map { LocalDay.today(at: $0, timeZone: timeZone) }
        let otherDay = momentDay.flatMap { $0 == pageDay ? nil : $0 }
        calendarDraft = CalendarDraft(
            time: line.start, unknownAttendees: [], suggestion: SuggestionFill(day: otherDay, names: waiting))
        guard let start = line.start else { return }
        includesTime = true
        selectedTime = start
    }
}

/// What the field holds of a journaling suggestion's line while it is not sent; it goes with the
/// text, as the calendar draft does.
struct SuggestionFill: Equatable {
    /// The moment's day when it is not the page's: the line is written to that day's file.
    var day: CalendarDate?
    /// Names no entity of their own kind answers to: chips, not text.
    var names: [SuggestionLine.Mention]
}
