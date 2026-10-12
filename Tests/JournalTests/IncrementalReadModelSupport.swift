import Foundation
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// Small fictional vault for incremental read-model equivalence (not a real diary).
enum IncrementalReadModelVault {
    static let today = CalendarDate("2026-10-05")!

    @discardableResult
    static func seed(at root: URL) throws -> URL {
        try write(root, ".app/vault.json", "{ \"formatVersion\": 1 }\n")
        try write(root, "templates/person.md", "---\ntype: person\n---\n")
        try write(root, "templates/place.md", "---\ntype: place\n---\n")
        try write(
            root, "people/Deniz Example.md",
            """
            ---
            type: person
            name: Deniz Example
            aliases: [Deniz]
            ---
            """)
        try write(
            root, "places/Harbor Cafe.md",
            """
            ---
            type: place
            name: Harbor Cafe
            ---
            """)
        try write(
            root, "goals/Reading.md",
            """
            ---
            type: goal
            name: Reading
            key: reading
            period: day
            kind: number
            target: 20
            unit: pages
            ---
            """)
        try write(
            root, "journal/2026-10-05.md",
            """
            ---
            type: journal
            date: 2026-10-05
            goals:
              reading: 5
            ---

            ## Tasks
            - [ ] Buy oats 📅 2026-10-05 ^task1
            - [ ] Call [[Deniz Example]] ^task2

            ## Events
            - 09:15 Coffee at [[Harbor Cafe]] ^evt1

            ## Journal
            Morning with [[Deniz Example]].
            """)
        try write(
            root, "journal/2026-10-04.md",
            """
            ---
            type: journal
            date: 2026-10-04
            ---

            ## Events
            - 18:00 Walk near [[Harbor Cafe]] ^evt2

            ## Journal
            Quiet evening.
            """)
        try write(root, "notes/Scratch.md", "- [ ] Loose note ^note1\n")
        return root
    }

    static func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    static func fullModel(index: VaultIndex, today: CalendarDate = today) throws -> VaultReadModel {
        VaultReadModel(snapshot: try index.snapshot(), today: today)
    }

    static func apply(
        _ previous: VaultReadModel, index: VaultIndex, result: RebuildResult, today: CalendarDate = today
    ) throws -> VaultReadModel {
        try VaultPublishedContent.applying(
            previous: previous, index: index, result: result, today: today
        ).content
    }
}

extension GraphInput {
    /// How the read model built the graph before it moved to a Core query: the oracle the query
    /// is compared with. Links from every file count; day mentions only from day files.
    init(snapshot: IndexSnapshot, entities: [EntitySummary]) {
        self.init()
        self.entities = entities.filter { Self.kinds.contains($0.kind) }
        let known = Set(self.entities.map(\.id))
        let dates = Dictionary(
            uniqueKeysWithValues: snapshot.files.compactMap { file -> (String, CalendarDate)? in
                guard file.kind == "day", let date = file.date.flatMap(CalendarDate.init) else { return nil }
                return (file.path, date)
            })
        var days: [CalendarDate: [String: Int]] = [:]
        for link in snapshot.links {
            guard let target = link.resolvedFile, known.contains(target) else { continue }
            totals[target, default: 0] += 1
            if let date = dates[link.file] { days[date, default: [:]][target, default: 0] += 1 }
        }
        self.days = days.map { Day(date: $0.key, mentions: $0.value) }.sorted { $0.date < $1.date }
    }
}

extension EntityTimeline {
    /// How the read model built every entity's timeline before it moved to a Core query: the
    /// oracle the query is compared with. Events and Journal paragraphs of day files, one row per
    /// block and linked file, newest day first, rows by descending file and block.
    static func build(snapshot: IndexSnapshot) -> [String: [EntityTimelineDay]] {
        let dates = Dictionary(
            uniqueKeysWithValues: snapshot.files.compactMap { file -> (String, CalendarDate)? in
                guard file.kind == "day", let value = file.date, let date = CalendarDate(value) else { return nil }
                return (file.path, date)
            })
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        var result: [String: [CalendarDate: [EntityTimelineRow]]] = [:]
        for block in snapshot.blocks
        where block.kind == "event" || (block.kind == "paragraph" && block.section == "Journal") {
            guard let date = dates[block.file] else { continue }
            let source = links[block.file] ?? []
            let targets = Set(source.filter { $0.block == block.ordinal }.compactMap(\.resolvedFile))
            for target in targets {
                result[target, default: [:]][date, default: []].append(
                    EntityTimelineRow(
                        file: block.file, ordinal: block.ordinal, text: LinkedText(row: block, links: source)))
            }
        }
        return result.mapValues { days in
            days.map {
                EntityTimelineDay(date: $0.key, rows: $0.value.sorted { ($0.file, $0.ordinal) > ($1.file, $1.ordinal) })
            }
            .sorted { $0.date > $1.date }
        }
    }

    /// The old read model's last encounter: the newest timeline date on or before `day`.
    static func lastEncounters(_ timelines: [String: [EntityTimelineDay]], asOf day: CalendarDate)
        -> [String: CalendarDate]
    {
        timelines.compactMapValues { $0.map(\.date).filter { $0 <= day }.max() }
    }

    /// Everything a timeline shows, as the read model's equality key compared it.
    static func key(_ days: [EntityTimelineDay]) -> [String] {
        days.map { day in
            let rows = day.rows.map { row in
                let spans = row.text.spans.map { "\($0.text):\($0.destination ?? ""):\($0.target ?? "")" }
                return "\(row.file)|\(row.ordinal)|\(row.text.plainText)|\(spans.joined(separator: ","))"
            }
            return "\(day.date)|\(rows.joined(separator: ";"))"
        }
    }
}
