import DateParsing
import EntityRecognition
import Foundation
import Observation
import VaultFormat
import VaultStore

@MainActor @Observable
final class QuickEntryModel {
    struct CreationRequest {
        let position: MentionPosition
        let spelling: String
    }

    struct Pin {
        var range: Range<Int>
        let entity: KnownEntity
    }

    enum Mode { case event, task }
    var mode = Mode.event {
        didSet {
            awaitingResolution = false
            overridesDate = false
            manualDueDate = nil
            manualDateIsAssumed = false
        }
    }
    var languages: [DateParsing.Language] =
        (Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first)?.hasPrefix("tr") == true
        ? [.turkish, .english] : [.english, .turkish]
    var overridesDate = false
    var manualDueDate: CalendarDate?
    var manualDateIsAssumed = false
    let today: () -> CalendarDate

    let store: IndexStore
    let day: CalendarDate?
    var selectedTime = Date()
    var text = "" {
        didSet { reconcile(oldText: oldValue) }
    }
    var includesTime = true
    var qualifier = ""
    var needsQualifier = false
    var creationKind: VaultEntityKind?
    private(set) var errorText: String?
    private(set) var isSubmitting = false
    private(set) var isCreating = false
    var awaitingResolution = false
    var requestedCreation: CreationRequest?
    var pins: [Pin] = []
    var skipped: Set<MentionPosition> = []

    init(store: IndexStore, day: CalendarDate? = nil, today: @escaping () -> CalendarDate = { LocalDay.today() }) {
        self.today = today
        self.store = store
        self.day = day
        includesTime = day == nil || day == LocalDay.today()
    }

    var isHistorical: Bool { day.map { $0 != LocalDay.today() } ?? false }
    var entryTime: LineClock? {
        guard mode == .event, includesTime else { return nil }
        return isHistorical ? LocalDay.clock(at: selectedTime) : LocalDay.clock()
    }

    var canSubmit: Bool {
        store.canAddEvent && !isSubmitting && !isCreating && !submissionText.allSatisfy(\.isWhitespace)
    }

    var mentions: [Mention] {
        EntityRecognizer.recognize(
            text, entities: store.knownEntities, usage: store.entityUsage,
            context: RecognitionContext(entities: pins.map(\.entity)))
    }

    var choices: [MentionPosition: String] {
        var result: [MentionPosition: String] = [:]
        for mention in mentions {
            if let pin = pins.first(where: { $0.range == globalRange(mention.position) }),
                mention.candidates.contains(where: { $0.file == pin.entity.file })
            {
                result[mention.position] = pin.entity.file
            }
        }
        return result
    }

    var pendingAmbiguity: Mention? {
        guard awaitingResolution, requestedCreation == nil else { return nil }
        return mentions.first { $0.isAmbiguous && choices[$0.position] == nil && !skipped.contains($0.position) }
    }

    var pendingUnknown: CreationRequest? {
        guard awaitingResolution, pendingAmbiguity == nil else { return nil }
        if let requestedCreation { return requestedCreation }
        return EntityRecognizer.unknownMentions(text, entities: store.knownEntities).first.map {
            CreationRequest(position: $0.position, spelling: $0.spelling)
        }
    }

    func choose(_ entity: KnownEntity, for mention: Mention) {
        pins.append(Pin(range: globalRange(mention.position), entity: entity))
    }

    func skip(_ mention: Mention) { skipped.insert(mention.position) }

    func dismissUnknown(_ mention: CreationRequest) {
        let range = globalRange(mention.position)
        replace((range.lowerBound - 1)..<range.lowerBound, with: "")
    }

    func create(_ kind: VaultEntityKind) async {
        guard !isCreating, let mention = pendingUnknown else { return }
        let draft = text
        let root = store.vaultURL
        isCreating = true
        errorText = nil
        creationKind = kind
        defer { isCreating = false }
        do {
            let entity = try await store.createEntity(
                kind: kind, name: mention.spelling, qualifier: needsQualifier ? qualifier : nil)
            needsQualifier = false
            qualifier = ""
            creationKind = nil
            requestedCreation = nil
            if text == draft && store.vaultURL == root {
                pins.append(Pin(range: globalRange(mention.position), entity: entity))
            }
        } catch VaultStoreError.nameTaken {
            guard text == draft && store.vaultURL == root else { return }
            needsQualifier = true
        } catch {
            guard text == draft && store.vaultURL == root else { return }
            errorText = String(localized: "Varlık oluşturulamadı. Kasayı kontrol edip yeniden dene.")
        }
    }

    @discardableResult
    func submit(time: LineClock?) async -> Bool {
        guard canSubmit else { return false }
        if mode == .task { prepareTaskText() }
        awaitingResolution = true
        guard pendingAmbiguity == nil, pendingUnknown == nil else { return false }
        isSubmitting = true
        errorText = nil
        defer { isSubmitting = false }
        let draft = text
        do {
            let linked = try EntityRecognizer.linking(text, mentions: mentions, choices: choices)
            let saved: Bool
            if mode == .task {
                saved = await store.addTask(on: today(), text: removingUnboundPrefixes(from: linked), due: dueDate)
            } else {
                saved = await store.addEvent(
                    on: day ?? LocalDay.today(), text: removingUnboundPrefixes(from: linked), time: time)
            }
            if saved && text == draft {
                text = ""
                overridesDate = false
                manualDueDate = nil
                manualDateIsAssumed = false
                pins = []
                skipped = []
                awaitingResolution = false
            }
            return saved
        } catch {
            errorText = String(localized: "Anmalar bağlanamadı. Metni kontrol edip yeniden dene.")
            return false
        }
    }

    private func removingUnboundPrefixes(from linked: String) -> String {
        let document = RawDocument(bytes: linked.utf8)
        var bytes = Array(linked.utf8)
        let remaining = EntityRecognizer.recognize(linked, entities: store.knownEntities)
        for mention in remaining.reversed() where mention.isExplicit {
            let offset = document.lines.prefix(mention.line).reduce(document.hasByteOrderMark ? 3 : 0) {
                $0 + $1.bytes.count
            }
            bytes.remove(at: offset + mention.byteRange.lowerBound - 1)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    func globalRange(_ position: MentionPosition) -> Range<Int> {
        let document = RawDocument(bytes: text.utf8)
        let offset = document.lines.prefix(position.line).reduce(document.hasByteOrderMark ? 3 : 0) {
            $0 + $1.bytes.count
        }
        return (offset + position.byteRange.lowerBound)..<(offset + position.byteRange.upperBound)
    }

    func replace(_ range: Range<Int>, with replacement: String) {
        var bytes = Array(text.utf8)
        bytes.replaceSubrange(range, with: replacement.utf8)
        text = String(decoding: bytes, as: UTF8.self)
    }

    private func reconcile(oldText: String) {
        guard oldText != text else { return }
        if mode == .task {
            let previous = DateExpressionParser.parse(oldText, today: today(), language: languages)?.date
            if previous != dateExpression?.date {
                overridesDate = false
                manualDueDate = nil
                manualDateIsAssumed = false
            }
        }
        let old = Array(oldText.utf8)
        let new = Array(text.utf8)
        let prefix = zip(old, new).prefix(while: { $0 == $1 }).count
        let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed())
            .prefix(while: { $0 == $1 }).count
        let oldEnd = old.count - suffix
        let delta = new.count - old.count
        pins = pins.compactMap { pin in
            if pin.range.upperBound <= prefix { return pin }
            if pin.range.lowerBound >= oldEnd {
                return Pin(range: (pin.range.lowerBound + delta)..<(pin.range.upperBound + delta), entity: pin.entity)
            }
            return nil
        }
        skipped = []
        awaitingResolution = false
        needsQualifier = false
        creationKind = nil
        requestedCreation = nil
        qualifier = ""
        errorText = nil
    }
}
