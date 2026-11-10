import Foundation
import VaultIndex

/// Index rows for one Markdown path, cut to what the read model still derives: the file, its
/// entity and aliases, its links, and how many event and task blocks it has. Block text
/// (paragraphs, headings, tasks, events) and goal values stay in the index; screens query them.
struct VaultFileFragment: Sendable, Equatable {
    var file: IndexSnapshot.File
    var entity: IndexedEntity?
    var aliases: [IndexedAlias]
    var links: [IndexedLink]
    /// Event blocks of the file (`IndexCounts.events`).
    var eventCount: Int
    /// Task blocks of the file (`IndexCounts.tasks`).
    var taskCount: Int
    /// First plain-text line of the first event block when this fragment is a day file.
    var firstEventPreview: String?
    /// The same line as display spans, its links kept (people and places drawn underlined); nil
    /// when the line has no link.
    var firstEventSpans: [DayPreviewSpan]?

    init(contents: IndexedFileContents) {
        self.init(
            file: contents.file, entity: contents.entity, aliases: contents.aliases, blocks: contents.blocks,
            links: contents.links)
    }

    /// Keeps of `blocks` only how many are events and tasks, plus the first event line for a day.
    init(
        file: IndexSnapshot.File, entity: IndexedEntity? = nil, aliases: [IndexedAlias] = [],
        blocks: [IndexedBlock] = [], links: [IndexedLink] = []
    ) {
        self.file = file
        self.entity = entity
        self.aliases = aliases
        self.links = links
        eventCount = blocks.count { $0.kind == "event" }
        taskCount = blocks.count { $0.kind == "task" }
        if file.kind == "day",
            let firstEvent = blocks.filter({ $0.kind == "event" }).min(by: { $0.ordinal < $1.ordinal })
        {
            if links.isEmpty {
                firstEventPreview = firstEvent.text.components(separatedBy: "\n").first
                firstEventSpans = nil
            } else {
                let linked = LinkedText(row: firstEvent, links: links)
                firstEventPreview = linked.plainText.components(separatedBy: "\n").first
                firstEventSpans = DayPreviewSpan.firstLine(of: linked)
            }
        } else {
            firstEventPreview = nil
            firstEventSpans = nil
        }
    }
}

extension VaultIndex {
    func loadFragment(path: String) throws -> VaultFileFragment? {
        try contents(ofFile: path).map(VaultFileFragment.init(contents:))
    }
}

/// One run of a day row's preview line: plain text or a link with its resolved path.
struct DayPreviewSpan: Sendable, Equatable {
    let text: String
    let destination: String?
    let target: String?

    /// The spans up to the first line break; nil when none of them is a link.
    static func firstLine(of text: LinkedText) -> [DayPreviewSpan]? {
        var result: [DayPreviewSpan] = []
        for span in text.spans {
            if let newline = span.text.firstIndex(of: "\n") {
                let head = String(span.text[..<newline])
                if !head.isEmpty {
                    result.append(DayPreviewSpan(text: head, destination: span.destination, target: span.target))
                }
                break
            }
            result.append(DayPreviewSpan(text: span.text, destination: span.destination, target: span.target))
        }
        return result.contains { $0.target != nil } ? result : nil
    }

    var linkedSpan: LinkedText.Span { LinkedText.Span(text: text, destination: destination, target: target) }
}
