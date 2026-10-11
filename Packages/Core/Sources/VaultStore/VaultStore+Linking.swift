import EntityRecognition
import Foundation
import VaultFormat
import VaultIndex

extension VaultStore {
    /// Links exactly one user-approved occurrence after revalidating its source on disk.
    ///
    /// The file is read again under the write queue. Unless the same block still holds the same first
    /// line and the recognizer still offers the entity at the same bytes of it, nothing is written and
    /// `staleTarget` is thrown. The link is the one `EntityRecognizer.linking` produces
    /// for a user's choice; a preceding at sign is removed with it. Every other byte is kept.
    @discardableResult
    public func linkingMention(_ mention: UnlinkedMention, to entity: KnownEntity) async throws -> RawDocument {
        try await perform {
            do {
                return try self.edit(mention.file, createDay: false) { document in
                    guard !document.isReadOnly else { throw EditError.readOnlyDocument }
                    let line = mention.position.line
                    let body = document.bodyLines
                    // Block equality covers the line range, the identifier and the first line's exact bytes.
                    guard mention.target.line == line,
                        (body.events.map(\.block) + body.tasks.map(\.block)).contains(mention.target)
                    else { throw VaultStoreError.staleTarget }
                    let entities = try self.index.unlinkedMentionEntities()
                    let text = String(decoding: document.serialized(), as: UTF8.self)
                    guard
                        let current = EntityRecognizer.recognize(text, entities: entities).first(where: {
                            $0.position == mention.position
                                && $0.candidates.contains(where: { $0.file == entity.file })
                        })
                    else { throw VaultStoreError.staleTarget }
                    let linked = RawDocument(
                        bytes: try EntityRecognizer.linking(
                            text, mentions: [current], choices: [current.position: entity.file]
                        ).utf8)
                    guard Self.isSingleLink(linked, replacing: current, in: document) else {
                        throw EntityLinkError.unrepresentableMention
                    }
                    return linked
                }
            } catch CocoaError.fileReadNoSuchFile {
                throw VaultStoreError.staleTarget
            }
        }
    }

    /// Whether the result differs from the source by one wikilink over the mention and reads the same otherwise.
    ///
    /// This is the last gate before old journal text is rewritten: a link that would move a block, change
    /// a clock, a task field or an identifier, or touch any byte outside the mention, is never written.
    static func isSingleLink(_ linked: RawDocument, replacing mention: Mention, in source: RawDocument) -> Bool {
        let line = mention.position.line
        guard linked.hasByteOrderMark == source.hasByteOrderMark, linked.lines.count == source.lines.count,
            linked.lines.indices.allSatisfy({ $0 == line || linked.lines[$0].bytes == source.lines[$0].bytes }),
            linked.lines[line].ending == source.lines[line].ending
        else { return false }
        let before = source.lines[line].content
        let after = linked.lines[line].content
        let start = mention.position.byteRange.lowerBound - (mention.isExplicit ? 1 : 0)
        let tail = before[mention.position.byteRange.upperBound...]
        guard start >= 0, after.count > start + tail.count, after.starts(with: before[..<start]),
            after.suffix(tail.count).elementsEqual(tail)
        else { return false }
        let link = Array(after[start..<(after.count - tail.count)])
        guard link.starts(with: [91, 91]), link.suffix(2).elementsEqual([93, 93]),
            linked.links.count == source.links.count + 1,
            linked.links.contains(where: { $0.line == line && $0.byteRange == start..<(start + link.count) })
        else { return false }
        let old = source.bodyLines
        let new = linked.bodyLines
        return old.events.map(BlockShape.init) == new.events.map(BlockShape.init)
            && old.tasks.map(BlockShape.init) == new.tasks.map(BlockShape.init)
    }
}

/// What an event or task means apart from its text.
private struct BlockShape: Equatable {
    let lines: Range<Int>
    let id: String?
    var time: EventTime?
    var status: String?
    var dates: [CalendarDate?] = []
    var priority: TaskPriority?
    var project: String?
    var recurrence: String?

    init(_ event: EventLine) {
        lines = event.block.lineRange
        id = event.block.id
        time = event.time
    }

    init(_ task: TaskLine) {
        lines = task.block.lineRange
        id = task.block.id
        status = task.rawStatus
        dates = [task.dueDate, task.startDate, task.doneDate]
        priority = task.priority
        project = task.project
        recurrence = task.recurrenceSource
    }
}
