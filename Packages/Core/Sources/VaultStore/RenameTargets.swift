import Foundation
import VaultFormat

/// Resolves freshly read targets using the pre-move filename ownership rules.
struct RenameTargets {
    let oldPath: String
    let newPath: String
    let files: [String]

    func matches(_ target: String) -> Bool {
        guard !target.isEmpty else { return false }
        var normalized = target
        while normalized.hasPrefix("/") || normalized.hasPrefix("./") {
            normalized.removeFirst(normalized.hasPrefix("./") ? 2 : 1)
        }
        let key = storeComparisonKey(normalized)
        let owner = files.first {
            let stem = String($0.dropLast(3))
            let candidate = target.contains("/") ? stem : (stem as NSString).lastPathComponent
            return storeComparisonKey(candidate).utf8.elementsEqual(key.utf8)
        }
        return owner == oldPath
    }

    func spelling(_ raw: String) -> String {
        let extensionText = raw.hasSuffix(".md") ? ".md" : ""
        let stem = extensionText.isEmpty ? raw : String(raw.dropLast(3))
        let gap = String(stem.reversed().prefix(while: { $0.isWhitespace }).reversed())
        let trimmed = String(stem.dropLast(gap.count))
        let directory = trimmed.lastIndex(of: "/").map { String(trimmed[...$0]) } ?? ""
        let basename = String((newPath as NSString).lastPathComponent.dropLast(3))
        return directory + basename + gap + extensionText
    }

    /// Body replacement uses only target ranges and retains every other byte, including BOM/endings.
    func body(_ document: RawDocument, links: [WikiLink]) throws -> RawDocument {
        guard !document.isReadOnly else { throw EditError.readOnlyDocument }
        var starts: [Int] = []
        var offset = document.hasByteOrderMark ? 3 : 0
        for line in document.lines {
            starts.append(offset)
            offset += line.bytes.count
        }
        var bytes = document.serialized()
        for link in links.sorted(by: { ($0.line, $0.targetRange.lowerBound) > ($1.line, $1.targetRange.lowerBound) }) {
            let range =
                (starts[link.line] + link.targetRange.lowerBound)..<(starts[link.line] + link.targetRange.upperBound)
            bytes.replaceSubrange(range, with: spelling(link.rawTarget).utf8)
        }
        return RawDocument(bytes: bytes)
    }

    /// A harmless prefix avoids interpreting a decoded YAML value as frontmatter or a fence.
    func text(_ text: String) throws -> String {
        let document = RawDocument(bytes: Array(("x " + text).utf8))
        var result = ""
        for line in document.lines {
            let prefixed = RawDocument(bytes: Array("x ".utf8) + line.content)
            let links = prefixed.links.filter { matches($0.target) }
            let changed = try body(prefixed, links: links)
            result += String(decoding: changed.serialized().dropFirst(2), as: UTF8.self)
            if let ending = line.ending { result += String(decoding: ending.bytes, as: UTF8.self) }
        }
        return String(decoding: result.utf8.dropFirst(2), as: UTF8.self)
    }
}
