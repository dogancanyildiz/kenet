import Foundation
import VaultFormat
import VaultIndex

extension QuickEntryModel {
    func projectSuggestionRange(at byteOffset: Int? = nil) -> Range<Int>? {
        guard mode == .task, !awaitingResolution else { return nil }
        let bytes = Array(text.utf8)
        let end = byteOffset ?? bytes.count
        guard end >= 0, end <= bytes.count else { return nil }
        let prefix = String(decoding: bytes[..<end], as: UTF8.self)
        guard let start = prefix.range(of: "#project/", options: .backwards),
            start.lowerBound == prefix.startIndex || prefix[prefix.index(before: start.lowerBound)].isWhitespace
        else { return nil }
        let fragment = prefix[start.upperBound...]
        guard !fragment.contains(where: { $0.isWhitespace || "[]#^`\\|<>".contains($0) }) else { return nil }
        // Match parser context so code, links and escaped tokens never offer a replacement.
        let probe = RawDocument(bytes: ("- [ ] " + String(prefix[..<start.upperBound]) + "probe").utf8)
        let tokenStart = 6 + prefix[..<start.lowerBound].utf8.count
        guard
            probe.bodyLines.tasks.first?.fieldRanges.contains(where: {
                $0.kind == .project && $0.byteRange.lowerBound == tokenStart
            }) == true
        else { return nil }
        var upper = end
        while upper < bytes.count, ![9, 10, 13, 32].contains(bytes[upper]) { upper += 1 }
        return prefix[..<start.lowerBound].utf8.count..<upper
    }

    func projectSuggestions(at byteOffset: Int? = nil) -> [String] {
        guard let range = projectSuggestionRange(at: byteOffset) else { return [] }
        let end = byteOffset ?? text.utf8.count
        let fragment = String(decoding: Array(text.utf8)[(range.lowerBound + 9)..<end], as: UTF8.self)
        let key = VaultIndex.projectKey(fragment)
        return Array(store.content.projects.filter { VaultIndex.projectKey($0).hasPrefix(key) }.prefix(6))
    }

    func selectProjectSuggestion(_ project: String, at byteOffset: Int? = nil) {
        guard let range = projectSuggestionRange(at: byteOffset), store.content.projects.contains(project) else {
            return
        }
        replace(range, with: "#project/" + project)
    }
}
