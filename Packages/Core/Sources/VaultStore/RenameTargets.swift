import Foundation
import VaultFormat

/// Resolves freshly read targets using the pre-move filename ownership rules.
struct RenameTargets {
    let oldPath: String
    let newPath: String
    private let comparisonKey: (String) -> String
    private let nameOwners: [[UInt8]: String]
    private let pathOwners: [[UInt8]: String]

    init(
        oldPath: String, newPath: String, files: [String],
        comparisonKey: @escaping (String) -> String = storeComparisonKey
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.comparisonKey = comparisonKey
        var names: [[UInt8]: String] = [:]
        var paths: [[UInt8]: String] = [:]
        for file in files {
            let stem = String(file.dropLast(3))
            let nameKey = Array(comparisonKey((stem as NSString).lastPathComponent).utf8)
            let pathKey = Array(comparisonKey(stem).utf8)
            // Retain the first owner in the supplied pre-move order, including collisions.
            if names[nameKey] == nil { names[nameKey] = file }
            if paths[pathKey] == nil { paths[pathKey] = file }
        }
        nameOwners = names
        pathOwners = paths
    }

    func matches(_ target: String) -> Bool {
        guard !target.isEmpty else { return false }
        var normalized = target
        while normalized.hasPrefix("/") || normalized.hasPrefix("./") {
            normalized.removeFirst(normalized.hasPrefix("./") ? 2 : 1)
        }
        let key = Array(comparisonKey(normalized).utf8)
        let owner = target.contains("/") ? pathOwners[key] : nameOwners[key]
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
