import EntityRecognition
import VaultFormat

/// Compare physical line content, retaining Markdown context across unchanged lines.
enum JournalRecognition {
    static func linkingChanges(in text: String, from original: String, entities: [KnownEntity]) throws -> String {
        let oldLines = RawDocument(bytes: original.utf8).lines.map(\.content)
        let newLines = RawDocument(bytes: text.utf8).lines.map(\.content)
        let difference = newLines.difference(from: oldLines)
        let changed = Set(
            difference.compactMap { change -> Int? in
                if case .insert(let offset, _, let associated) = change, associated == nil { return offset + 1 }
                return nil
            })
        // A body-leading horizontal rule must not be interpreted as frontmatter.
        let prefix = "## Journal\n"
        let source = prefix + text
        let mentions = EntityRecognizer.recognize(source, entities: entities).filter {
            $0.isCertain && changed.contains($0.line)
        }
        return String(try EntityRecognizer.linking(source, mentions: mentions).dropFirst(prefix.count))
    }

    static func body(of document: RawDocument) throws -> String {
        guard !document.isReadOnly else { throw EditError.readOnlyDocument }
        guard let section = document.daySections.section(.journal) else { return "" }
        let bytes = document.lines[(section.headingLine + 1)..<section.lineRange.upperBound].flatMap(\.bytes)
        return String(decoding: bytes, as: UTF8.self)
    }
}
