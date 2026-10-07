import EntityRecognition
import VaultFormat

/// Compare physical line content, retaining Markdown context across unchanged lines.
enum JournalRecognition {
    /// 0-based body line indices whose content is new relative to `original` (inserts / edits).
    static func changedLineIndices(in text: String, from original: String) -> Set<Int> {
        let oldLines = RawDocument(bytes: original.utf8).lines.map(\.content)
        let newLines = RawDocument(bytes: text.utf8).lines.map(\.content)
        return Set(
            newLines.difference(from: oldLines).compactMap { change -> Int? in
                if case .insert(let offset, _, let associated) = change, associated == nil {
                    return offset
                }
                return nil
            })
    }

    static func linkingChanges(
        in text: String, from original: String, entities: [KnownEntity],
        context: [KnownEntity] = [], choices: [MentionPosition: String] = [:]
    ) throws -> String {
        // Prefixed document line numbers are body index + 1 (synthetic `## Journal` heading).
        let changed = Set(changedLineIndices(in: text, from: original).map { $0 + 1 })
        // A body-leading horizontal rule must not be interpreted as frontmatter.
        let prefix = "## Journal\n"
        let source = prefix + text
        // Remap body choices (+0 lines) onto the prefixed document (+1 for the synthetic heading).
        var remapped: [MentionPosition: String] = [:]
        for (position, file) in choices {
            remapped[
                MentionPosition(line: position.line + 1, byteRange: position.byteRange)] = file
        }
        let mentions = EntityRecognizer.recognize(
            source, entities: entities, context: RecognitionContext(entities: context)
        ).filter {
            ($0.isCertain || remapped[$0.position] != nil) && changed.contains($0.line)
        }
        return String(
            try EntityRecognizer.linking(source, mentions: mentions, choices: remapped)
                .dropFirst(prefix.count))
    }

    static func body(of document: RawDocument) throws -> String {
        guard !document.isReadOnly else { throw EditError.readOnlyDocument }
        guard let section = document.daySections.section(.journal) else { return "" }
        let bytes = document.lines[(section.headingLine + 1)..<section.lineRange.upperBound].flatMap(\.bytes)
        return String(decoding: bytes, as: UTF8.self)
    }
}
