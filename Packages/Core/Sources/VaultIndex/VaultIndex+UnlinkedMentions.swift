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
    /// A digest of the day file's bytes as the query read them.
    package let fileDigest: UInt64
    /// Whether another event or task of that file had the same first line, byte for byte.
    package let hasTwin: Bool

    /// FNV-1a over a file's bytes: enough to tell whether it changed between the query and the write.
    package static func digest(_ bytes: some Sequence<UInt8>) -> UInt64 {
        bytes.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }

    /// The wikilink the app writes over a spelling: the entity's target, with the spelling as display
    /// text unless it is the target itself. `nil` for a spelling that cannot stand inside a wikilink.
    package static func link(to entity: KnownEntity, over spelling: some Collection<UInt8>) -> [UInt8]? {
        guard !spelling.contains(where: { $0 == 91 || $0 == 93 }) else { return nil }
        let target = Array(entity.linkTarget.utf8)
        let display = !spelling.elementsEqual(target) || entity.qualifier != nil
        return [91, 91] + target + (display ? [124] + spelling : []) + [93, 93]
    }
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
    /// Task continuation lines, Journal paragraphs, notes, an event's clock and task fields are not listed,
    /// and neither is a spelling whose link the writer would refuse: one that cannot stand inside a
    /// wikilink, or one inside a recurrence rule the app cannot read.
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

    /// Reads each day once and recognizes every event and task first line of all of them in one pass.
    ///
    /// The recognizer judges a line by its own bytes unless it lies in frontmatter or a fence, and the
    /// body parser never takes a block from either, so a first line reads the same here as in its file.
    func unlinkedMentions(
        of entity: KnownEntity, entities: [KnownEntity], days: [(path: String, date: String)], vaultRoot: URL
    ) throws -> [UnlinkedMention] {
        let root = vaultRoot.resolvingSymlinksInPath().standardizedFileURL
        var sources: [UnlinkedMentionSource] = []
        var firstLines: [UInt8] = []
        for day in days {
            let url = root.appendingPathComponent(day.path).standardizedFileURL
            // An unreadable, vanished or symlinked file has nothing the user can act on.
            guard let date = CalendarDate(day.date), url == url.resolvingSymlinksInPath(),
                let data = try? readFile(url)
            else { continue }
            let document = RawDocument(bytes: data)
            guard !document.isReadOnly else { continue }
            let body = document.bodyLines
            let scopes = body.events.map { UnlinkedMentionScope($0.block) } + body.tasks.map(UnlinkedMentionScope.init)
            var repeats: [[UInt8]: Int] = [:]
            for scope in scopes { repeats[scope.block.firstLineContent, default: 0] += 1 }
            let digest = UnlinkedMention.digest(data)
            for scope in scopes {
                sources.append(
                    UnlinkedMentionSource(
                        file: day.path, date: date, scope: scope, digest: digest,
                        hasTwin: repeats[scope.block.firstLineContent, default: 0] > 1))
                firstLines += scope.block.firstLineContent + [10]
            }
        }
        var result: [UnlinkedMention] = []
        for mention in EntityRecognizer.recognize(String(decoding: firstLines, as: UTF8.self), entities: entities) {
            guard mention.candidates.contains(where: { $0.file == entity.file }), sources.indices.contains(mention.line)
            else { continue }
            let source = sources[mention.line]
            guard source.scope.contains(mention.byteRange),
                source.scope.keepsFields(linking: mention.byteRange, isExplicit: mention.isExplicit, to: entity)
            else { continue }
            result.append(
                UnlinkedMention(
                    file: source.file, date: source.date, target: source.scope.block,
                    lineText: String(decoding: source.scope.block.firstLineContent, as: UTF8.self),
                    position: MentionPosition(line: source.scope.block.line, byteRange: mention.byteRange),
                    spelling: mention.spelling, isExplicit: mention.isExplicit,
                    isAmbiguous: mention.isAmbiguous, isCaseMismatch: mention.isCaseMismatch,
                    fileDigest: source.digest, hasTwin: source.hasTwin))
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.file != $1.file { return $0.file < $1.file }
            return ($0.position.line, $0.position.byteRange.lowerBound)
                < ($1.position.line, $1.position.byteRange.lowerBound)
        }
    }
}

/// One event or task first line of a day file as the query read it.
struct UnlinkedMentionSource {
    let file: String
    let date: CalendarDate
    let scope: UnlinkedMentionScope
    let digest: UInt64
    let hasTwin: Bool
}

/// The user's text within an event or task first line: no list marker, clock, checkbox, field or identifier.
struct UnlinkedMentionScope {
    let block: LineBlock
    let text: Range<Int>
    let fields: [Range<Int>]
    let task: TaskLine?

    init(_ task: TaskLine) {
        self.init(task.block, fields: task.fieldRanges.map(\.byteRange), task: task)
    }

    init(_ block: LineBlock, fields: [Range<Int>] = [], task: TaskLine? = nil) {
        self.block = block
        self.fields = fields
        self.task = task
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

    /// Whether the entity's link can replace the range and the task still reads the same fields.
    ///
    /// A recurrence rule the app cannot read has no field range, yet it runs to the end of the line:
    /// a link inside it would change the rule's source text, which the writer refuses.
    func keepsFields(linking range: Range<Int>, isExplicit: Bool, to entity: KnownEntity) -> Bool {
        let content = block.firstLineContent
        let start = range.lowerBound - (isExplicit ? 1 : 0)
        guard start >= 0, let link = UnlinkedMention.link(to: entity, over: content[range]) else { return false }
        guard let task else { return true }
        let linked = RawDocument(bytes: content[..<start] + link + content[range.upperBound...])
        guard let after = linked.bodyLines.tasks.first else { return false }
        return after.rawStatus == task.rawStatus && after.block.id == block.id && after.dueDate == task.dueDate
            && after.startDate == task.startDate && after.doneDate == task.doneDate && after.priority == task.priority
            && after.project == task.project && after.recurrenceSource == task.recurrenceSource
    }
}
