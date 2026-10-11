import EntityRecognition
import Foundation
import GRDB
import VaultFormat

/// One plain spelling of an entity in a day's event or task line, with its lossless write target.
public struct UnlinkedMention: Sendable, Equatable {
    /// The vault-relative day file.
    public let file: String
    /// The day the file belongs to.
    public let date: CalendarDate
    /// The event or task whose first line holds the spelling.
    public let target: LineBlock
    /// The first line's exact content, excluding its terminator.
    public let lineText: String
    /// The zero-based physical line and the spelling's UTF-8 range within `lineText`.
    public let position: MentionPosition
    /// The source spelling, excluding an at sign and an apostrophe suffix.
    public let spelling: String
    /// Whether an at sign precedes the spelling; linking removes it, as every other app write does.
    public let isExplicit: Bool
    /// Whether the spelling also names another entity.
    public let isAmbiguous: Bool
    /// Whether the initial letter's case differs from every matching name and alias.
    public let isCaseMismatch: Bool
}

extension VaultIndex {
    /// Every entity the recognizer may bind, so that ambiguity is judged against the whole vault.
    package func unlinkedMentionEntities() throws -> [KnownEntity] {
        let kinds = try database.read { try String.fetchAll($0, sql: "SELECT DISTINCT kind FROM entities") }
        return try knownEntities(kinds: Set(kinds))
    }

    /// Plain spellings of the entity's name or aliases in day event and task first lines, newest day first.
    ///
    /// Full-text search narrows the day files; the recognizer then reads their current bytes with its
    /// usual name rules, so code, existing links, addresses and suffixes behave as in every app write.
    /// Task continuation lines, Journal paragraphs, notes, an event's clock and task fields are not listed.
    public func unlinkedMentions(of entity: KnownEntity, vaultRoot: URL) throws -> [UnlinkedMention] {
        let entities = try unlinkedMentionEntities()
        // An entity whose file name cannot be a wikilink target has no mention the writer could link.
        guard let current = entities.first(where: { $0.file == entity.file }), !current.linkTarget.isEmpty,
            !current.linkTarget.contains(where: { EntityRecognizer.unrepresentableLinkTargetCharacters.contains($0) })
        else { return [] }
        return try unlinkedMentions(
            of: current, entities: entities, days: try unlinkedMentionDays(naming: current), vaultRoot: vaultRoot)
    }

    /// Day files with an event or task whose text holds every word of a name; `nil` lists every day file.
    ///
    /// The search uses the index tokenizer, which splits at punctuation, hyphens and apostrophes, where
    /// the recognizer lets a name end; the recognizer decides everything else. A name's words must share
    /// one block, in any order. The lowercase spelling is searched too when lowercasing changes its
    /// length, which covers `İ` written as `i` with a combining dot. A name without a letter or digit
    /// has no searchable word, so every day file is read instead.
    func unlinkedMentionDays(naming entity: KnownEntity?) throws -> [(path: String, date: String)] {
        var expressions: Set<String>?
        if let entity {
            expressions = []
            for name in [entity.name] + entity.aliases where !name.allSatisfy(\.isWhitespace) {
                let lowercased = name.lowercased()
                let spellings =
                    lowercased.unicodeScalars.count == name.unicodeScalars.count ? [name] : [name, lowercased]
                for spelling in spellings {
                    let words = spelling.split(whereSeparator: \.isWhitespace)
                        .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
                    if let expression = searchExpression(words.joined(separator: " ")) {
                        expressions?.insert(expression)
                    } else {
                        expressions = nil
                    }
                }
            }
        }
        return try database.read { db in
            var rows: [Row] = []
            if let expressions {
                for expression in expressions.sorted() {
                    rows += try Row.fetchAll(
                        db,
                        sql: """
                            SELECT DISTINCT f.path, f.date FROM search
                            JOIN files f ON f.path = search.file
                            JOIN blocks b ON b.file = search.file AND b.ordinal = search.block
                            WHERE search MATCH ? AND f.kind = 'day' AND f.date IS NOT NULL
                                AND b.kind IN ('event', 'task')
                            """, arguments: [expression])
                }
            } else {
                rows = try Row.fetchAll(
                    db, sql: "SELECT path, date FROM files WHERE kind = 'day' AND date IS NOT NULL")
            }
            var seen: Set<String> = []
            return rows.map { (path: $0["path"] as String, date: $0["date"] as String) }
                .filter { seen.insert($0.path).inserted }
        }
    }

    func unlinkedMentions(
        of entity: KnownEntity, entities: [KnownEntity], days: [(path: String, date: String)], vaultRoot: URL
    ) throws -> [UnlinkedMention] {
        let root = vaultRoot.resolvingSymlinksInPath().standardizedFileURL
        var result: [UnlinkedMention] = []
        for day in days {
            let url = root.appendingPathComponent(day.path).standardizedFileURL
            // An unreadable, vanished or symlinked file has nothing the user can act on.
            guard let date = CalendarDate(day.date), url == url.resolvingSymlinksInPath(),
                let data = try? readFile(url)
            else { continue }
            let document = RawDocument(bytes: data)
            guard !document.isReadOnly else { continue }
            let body = document.bodyLines
            var scopes: [Int: UnlinkedMentionScope] = [:]
            for event in body.events { scopes[event.block.line] = UnlinkedMentionScope(event.block) }
            for task in body.tasks {
                scopes[task.block.line] = UnlinkedMentionScope(task.block, fields: task.fieldRanges.map(\.byteRange))
            }
            let text = String(decoding: document.serialized(), as: UTF8.self)
            for mention in EntityRecognizer.recognize(text, entities: entities) {
                guard mention.candidates.contains(where: { $0.file == entity.file }),
                    let scope = scopes[mention.line], scope.contains(mention.byteRange)
                else { continue }
                result.append(
                    UnlinkedMention(
                        file: day.path, date: date, target: scope.block,
                        lineText: String(decoding: scope.block.firstLineContent, as: UTF8.self),
                        position: mention.position, spelling: mention.spelling, isExplicit: mention.isExplicit,
                        isAmbiguous: mention.isAmbiguous, isCaseMismatch: mention.isCaseMismatch))
            }
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.file != $1.file { return $0.file < $1.file }
            return ($0.position.line, $0.position.byteRange.lowerBound)
                < ($1.position.line, $1.position.byteRange.lowerBound)
        }
    }
}

/// The user's text within an event or task first line: no list marker, clock, checkbox, field or identifier.
struct UnlinkedMentionScope {
    let block: LineBlock
    let text: Range<Int>
    let fields: [Range<Int>]

    init(_ block: LineBlock, fields: [Range<Int>] = []) {
        self.block = block
        self.fields = fields
        let content = block.firstLineContent
        var end = content.count
        if let id = block.id {
            while end > 0, content[end - 1] == 32 || content[end - 1] == 9 { end -= 1 }
            end -= id.utf8.count + 2
        }
        let start = end - block.text.utf8.count
        // The parsed text is the slice that ends where the identifier begins. A line that does not
        // fit that shape is not one this query understands, and its empty scope lists nothing.
        if start >= 0, end <= content.count, content[start..<end].elementsEqual(block.text.utf8) {
            text = start..<end
        } else {
            text = 0..<0
        }
    }

    func contains(_ range: Range<Int>) -> Bool {
        text.lowerBound <= range.lowerBound && range.upperBound <= text.upperBound
            && !fields.contains(where: { $0.overlaps(range) })
    }
}
