import EntityRecognition
import Foundation
import VaultStore

extension QuickEntryModel {
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
        // TextField entries are one physical line; recognition supplies multiline positions on send.
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
}
