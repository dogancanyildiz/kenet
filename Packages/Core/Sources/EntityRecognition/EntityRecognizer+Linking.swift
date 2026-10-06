import VaultFormat

/// Failures that prevent producing a faithful wikilink replacement.
public enum EntityLinkError: Error, Sendable, Equatable {
    /// The selected source spelling or its explicit prefix no longer matches.
    case staleMention
    /// A selected path is not one of the mention's candidates.
    case invalidChoice
    /// The target or display text cannot be written in wikilink syntax.
    case unrepresentableMention
}

extension EntityRecognizer {
    /// Characters that cannot appear in a wikilink target path.
    public static let unrepresentableLinkTargetCharacters = Set("\\:*?\"<>|#^[]\n\r")

    /// Links certain mentions and explicit candidate choices, preserving every other byte.
    public static func linking(
        _ text: String, mentions: [Mention], choices: [MentionPosition: String] = [:]
    ) throws -> String {
        let document = RawDocument(bytes: text.utf8)
        let bytes = Array(text.utf8)
        var starts: [Int] = []
        var offset = document.hasByteOrderMark ? 3 : 0
        for line in document.lines {
            starts.append(offset)
            offset += line.bytes.count
        }
        var edits: [(range: Range<Int>, bytes: [UInt8])] = []
        for mention in mentions {
            let selected: KnownEntity
            if let choice = choices[mention.position] {
                guard let candidate = mention.candidates.first(where: { $0.file == choice }) else {
                    throw EntityLinkError.invalidChoice
                }
                selected = candidate
            } else if mention.isCertain {
                selected = mention.candidates[0]
            } else {
                continue
            }
            let position = mention.position
            guard document.lines.indices.contains(position.line) else { throw EntityLinkError.staleMention }
            let line = document.lines[position.line].content
            let range = position.byteRange
            guard range.lowerBound >= 0, range.upperBound <= line.count, !range.isEmpty,
                line[range].elementsEqual(mention.spelling.utf8)
            else { throw EntityLinkError.staleMention }
            let target = selected.linkTarget
            guard !mention.spelling.contains(where: { "[]\n\r".contains($0) }) else {
                throw EntityLinkError.unrepresentableMention
            }
            guard !target.isEmpty,
                !target.contains(where: { unrepresentableLinkTargetCharacters.contains($0) })
            else {
                continue
            }
            let exactTarget = mention.spelling.utf8.elementsEqual(target.utf8)
            let display = !exactTarget || selected.qualifier != nil
            let table = line.drop(while: { $0 == 32 || $0 == 9 }).first == 124
            let separator = table ? "\\|" : "|"
            let link = "[[" + target + (display ? separator + mention.spelling : "") + "]]"
            var start = range.lowerBound
            if mention.isExplicit {
                guard start > 0, line[start - 1] == 64 else { throw EntityLinkError.staleMention }
                start -= 1
            }
            edits.append(
                ((starts[position.line] + start)..<(starts[position.line] + range.upperBound), Array(link.utf8)))
        }
        edits.sort { $0.range.lowerBound < $1.range.lowerBound }
        var result: [UInt8] = []
        var cursor = 0
        for edit in edits {
            guard edit.range.lowerBound >= cursor else { throw EntityLinkError.staleMention }
            result.append(contentsOf: bytes[cursor..<edit.range.lowerBound])
            result.append(contentsOf: edit.bytes)
            cursor = edit.range.upperBound
        }
        result.append(contentsOf: bytes[cursor...])
        return String(decoding: result, as: UTF8.self)
    }

}
