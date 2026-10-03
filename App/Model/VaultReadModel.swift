import Foundation
import VaultFormat
import VaultIndex

/// Immutable screen data published together with the index counts.
struct VaultReadModel: Sendable {
    var days: [DaySummary] = []
    var entities: [EntitySummary] = []

    static let empty = VaultReadModel()

    init() {}

    init(snapshot: IndexSnapshot) {
        let blocks = Dictionary(grouping: snapshot.blocks, by: \.file)
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        let aliases = Dictionary(grouping: snapshot.aliases, by: \.file)
        let incoming = Dictionary(grouping: snapshot.links.compactMap(\.resolvedFile), by: { $0 })
        entities = snapshot.entities.filter { ["person", "place"].contains($0.kind) }.map { entity in
            EntitySummary(
                id: entity.file, kind: entity.kind, name: entity.name, qualifier: entity.qualifier,
                aliases: (aliases[entity.file] ?? []).sorted { $0.ordinal < $1.ordinal }.map(\.name),
                incomingLinks: incoming[entity.file]?.count ?? 0)
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            let qualifier = ($0.qualifier ?? "").localizedStandardCompare($1.qualifier ?? "")
            return qualifier == .orderedSame ? $0.id < $1.id : qualifier == .orderedAscending
        }
        days = snapshot.files.compactMap { file in
            guard file.kind == "day", let value = file.date, let date = CalendarDate(value) else { return nil }
            let rows = (blocks[file.path] ?? []).sorted { $0.ordinal < $1.ordinal }
            let sourceLinks = links[file.path] ?? []
            let events = rows.filter { $0.kind == "event" }.map { row in
                EventRow(
                    id: row.ordinal,
                    time: row.time.flatMap {
                        RawDocument(bytes: Array("## Events\n- \($0) event".utf8)).bodyLines.events.first?.time
                    },
                    text: LinkedText(row: row, links: sourceLinks),
                    sourceLine: row.firstLine - 1, sourceEnd: row.lastLine,
                    sourceText: row.text, sourceIdentifier: row.identifier)
            }
            let journal = rows.filter { $0.section == "Journal" && ["paragraph", "heading"].contains($0.kind) }
                .map { row in
                    JournalRow(
                        id: row.ordinal, headingLevel: row.headingLevel,
                        text: LinkedText(row: row, links: sourceLinks))
                }
            return DaySummary(id: file.path, date: date, events: events, journal: journal)
        }.sorted { $0.date > $1.date }
    }

    func day(on date: CalendarDate) -> DaySummary {
        days.first { $0.date == date }
            ?? DaySummary(id: "journal/\(date).md", date: date, events: [], journal: [])
    }
}

/// A source-ordered day and its read-only journal paragraphs.
struct DaySummary: Identifiable, Sendable {
    let id: String
    let date: CalendarDate
    let events: [EventRow]
    let journal: [JournalRow]

    var preview: String? {
        journal.first { $0.headingLevel == nil }?.text.plainText.components(separatedBy: "\n").first
    }
}

struct EventRow: Identifiable, Sendable {
    let id: Int
    let time: EventTime?
    let text: LinkedText
    let sourceLine: Int
    let sourceEnd: Int
    let sourceText: String
    let sourceIdentifier: String?
}

struct JournalRow: Identifiable, Sendable {
    let id: Int
    let headingLevel: Int?
    let text: LinkedText
}

/// The entity fields needed before the timeline screen is implemented.
struct EntitySummary: Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let name: String
    let qualifier: String?
    let aliases: [String]
    let incomingLinks: Int
}
