import EntityRecognition
import Foundation
import Observation
import VaultFormat
import VaultStore

/// Shared @-mention draft state used by quick entry, event editing, and journal writing.
@MainActor @Observable
final class MentionComposer {
    struct CreationRequest {
        let position: MentionPosition
        let spelling: String
    }

    struct Pin {
        var range: Range<Int>
        let entity: KnownEntity
    }

    let store: IndexStore
    var text = "" {
        didSet { reconcile(oldText: oldValue) }
    }
    var qualifier = ""
    var needsQualifier = false
    var creationKind: VaultEntityKind?
    var errorText: String?
    private(set) var isCreating = false
    var awaitingResolution = false
    var requestedCreation: CreationRequest?
    var pins: [Pin] = []
    var skipped: Set<MentionPosition> = []

    init(store: IndexStore, text: String = "") {
        self.store = store
        self.text = text
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

    /// Arms resolution and returns whether commit can proceed without a strip choice.
    func beginResolution() -> Bool {
        awaitingResolution = true
        return pendingAmbiguity == nil && pendingUnknown == nil
    }

    func linkedText() throws -> String {
        let linked = try EntityRecognizer.linking(text, mentions: mentions, choices: choices)
        return removingUnbound(from: linked)
    }

    /// Strips leftover explicit `@` markers after linking (file bytes never keep `@`).
    func removingUnbound(from linked: String) -> String {
        removingUnboundPrefixes(from: linked)
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

    /// Suggestions follow the active mention at the insertion point, defaulting to the end.
    func suggestionRange(at byteOffset: Int? = nil) -> Range<Int>? {
        let bytes = Array(text.utf8)
        let end = byteOffset ?? bytes.count
        guard end >= 0, end <= bytes.count else { return nil }
        let prefix = String(decoding: bytes[..<end], as: UTF8.self)
        guard let at = prefix.lastIndex(of: "@") else { return nil }
        if at != prefix.startIndex {
            let previous = prefix[prefix.index(before: at)]
            guard previous.isWhitespace || "(,;".contains(previous) else { return nil }
        }
        let fragment = prefix[prefix.index(after: at)...]
        guard fragment.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }),
            !fragment.hasSuffix(" ")
        else { return nil }
        return prefix[..<at].utf8.count..<end
    }

    func suggestions(at byteOffset: Int? = nil) -> [KnownEntity] {
        guard !awaitingResolution, let range = suggestionRange(at: byteOffset) else { return [] }
        let fragment = String(decoding: Array(text.utf8)[(range.lowerBound + 1)..<range.upperBound], as: UTF8.self)
        let key = fragment.precomposedStringWithCanonicalMapping.lowercased()
        let dates = Dictionary(
            uniqueKeysWithValues: store.entityUsage.map { ($0.file, $0.lastDate?.description ?? "") })
        return Array(
            store.knownEntities.filter {
                key.isEmpty
                    || ([$0.name] + $0.aliases).contains {
                        $0.precomposedStringWithCanonicalMapping.lowercased().contains(key)
                    }
            }.sorted {
                let left = dates[$0.file] ?? ""
                let right = dates[$1.file] ?? ""
                if left != right { return left > right }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.file < $1.file
            }.prefix(6))
    }

    func beginCreation(_ kind: VaultEntityKind, at byteOffset: Int? = nil) async {
        guard let range = suggestionRange(at: byteOffset), range.count > 1 else { return }
        let positionRange = (range.lowerBound + 1)..<range.upperBound
        let name = String(decoding: Array(text.utf8)[positionRange], as: UTF8.self)
        let prefix = String(decoding: Array(text.utf8)[..<positionRange.lowerBound], as: UTF8.self)
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        requestedCreation = CreationRequest(
            position: MentionPosition(
                line: lines.count - 1,
                byteRange: (lines.last?.utf8.count ?? 0)..<((lines.last?.utf8.count ?? 0) + name.utf8.count)),
            spelling: name)
        awaitingResolution = true
        creationKind = kind
        if store.knownEntities.contains(where: {
            $0.name.precomposedStringWithCanonicalMapping.lowercased()
                == name.precomposedStringWithCanonicalMapping.lowercased()
        }) {
            needsQualifier = true
            return
        }
        await create(kind)
    }

    func selectSuggestion(_ entity: KnownEntity, at byteOffset: Int? = nil) {
        guard let range = suggestionRange(at: byteOffset) else { return }
        replace(range, with: entity.name)
        pins.append(Pin(range: range.lowerBound..<(range.lowerBound + entity.name.utf8.count), entity: entity))
    }

    func pin(_ entity: KnownEntity, nameRange: Range<Int>) {
        pins.append(Pin(range: nameRange, entity: entity))
    }

    func clearResolutionState() {
        awaitingResolution = false
        needsQualifier = false
        creationKind = nil
        requestedCreation = nil
        qualifier = ""
        errorText = nil
    }

    func resetPins() {
        pins = []
        skipped = []
        clearResolutionState()
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

    private func reconcile(oldText: String) {
        guard oldText != text else { return }
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
        clearResolutionState()
    }
}
