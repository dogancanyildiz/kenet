import Foundation
import GoalTracking
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
    /// The graph rebuilt from the index snapshot instead of the Core query: the oracle the query is
    /// compared with. Links from every file count; day mentions only from day files (the read
    /// model's construction before the query existed). Groups are an independent build of the block
    /// rule over the snapshot: entities sharing an event or task block, or one segment
    /// (`ParagraphSegments`) of a paragraph block, of a day file.
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
        struct Entry: Hashable {
            let date: CalendarDate
            let file: String
            let block: Int
            let segment: Int
        }
        let blocks = Dictionary(grouping: snapshot.blocks, by: \.file).mapValues {
            Dictionary(uniqueKeysWithValues: $0.map { ($0.ordinal, $0) })
        }
        var members: [Entry: Set<String>] = [:]
        for link in snapshot.links {
            guard let ordinal = link.block, let target = link.resolvedFile, known.contains(target),
                let date = dates[link.file], let block = blocks[link.file]?[ordinal],
                ["event", "task", "paragraph"].contains(block.kind)
            else { continue }
            let segment =
                block.kind == "paragraph"
                ? ParagraphSegments.index(ofLine: link.line - block.firstLine, in: block.text) : 0
            members[Entry(date: date, file: link.file, block: ordinal, segment: segment), default: []].insert(target)
        }
        var groups: [CalendarDate: Set<[String]>] = [:]
        for (entry, entities) in members where entities.count >= 2 {
            groups[entry.date, default: []].insert(entities.sorted())
        }
        self.days = days.map {
            Day(
                date: $0.key, mentions: $0.value,
                groups: groups[$0.key, default: []].sorted { $0.lexicographicallyPrecedes($1) })
        }.sorted { $0.date < $1.date }
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

extension DaySummary {
    /// How the read model built its `days` before they moved to Core queries: the oracle the
    /// queries are compared with. Day files newest first (path on ties), each with its events and
    /// Journal paragraphs and headings in source order.
    static func build(snapshot: IndexSnapshot) -> [DaySummary] {
        let goalFiles = Set(snapshot.goalLogs.map(\.file))
        let blocks = Dictionary(grouping: snapshot.blocks, by: \.file)
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        return snapshot.files.compactMap { file -> DaySummary? in
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
            return DaySummary(
                id: file.path, date: date, events: events, journal: journal,
                hasGoalRecords: goalFiles.contains(file.path))
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id < $1.id
        }
    }

    /// The old `day(on:)` over a built list: a date without a day file is empty.
    static func day(on date: CalendarDate, in days: [DaySummary]) -> DaySummary {
        days.first { $0.date == date } ?? DaySummary(id: "journal/\(date).md", date: date, events: [], journal: [])
    }

    /// Everything a day shows, as the read model's equality key compared it.
    var key: String {
        func spans(_ text: LinkedText) -> String {
            text.spans.map { "\($0.text):\($0.destination ?? ""):\($0.target ?? "")" }.joined(separator: ",")
        }
        let eventKeys = events.map {
            "\($0.id)|\($0.time?.raw ?? "")|\($0.text.plainText)|\($0.sourceLine)|\($0.sourceEnd)|\($0.sourceText)|\($0.sourceIdentifier ?? "")|\(spans($0.text))"
        }.joined(separator: ";")
        let journalKeys = journal.map {
            "\($0.id)|\($0.headingLevel.map(String.init) ?? "")|\($0.text.plainText)|\(spans($0.text))"
        }.joined(separator: ";")
        return "\(id)|\(date)|\(hasGoalRecords)|\(eventKeys)|\(journalKeys)"
    }

    /// The list row and calendar mark the old read model gave this day.
    var overview: DayOverview {
        DayOverview(
            id: id, date: date, eventCount: events.count, journalCount: journal.count, preview: preview,
            hasGoalRecords: hasGoalRecords)
    }
}

extension IndexStore {
    /// Every day as the old `days` field listed them, newest first, read through the day queries
    /// the screens run. Lets store tests check what the index holds after a write.
    func days() async throws -> [DaySummary] {
        var days: [DaySummary] = []
        for overview in try await computeDaySummaries() { days.append(try await computeDay(on: overview.date)) }
        return days
    }

    /// Every task as the old `tasks` field listed them (file and line), read through the task
    /// queries the screens run: every open and cancelled task and every done one.
    func allTasks() async throws -> [TaskRow] {
        let board = try await computeBoardTasks(
            doneFrom: CalendarDate("1000-01-01")!, to: CalendarDate("9999-12-31")!, includeCancelled: true)
        let done = try await computeCompletedTasks(limit: Int.max)
        var seen: Set<String> = []
        return (board + done).filter { seen.insert($0.id).inserted }.sorted(by: TaskRow.sourceOrder)
    }
}

extension TaskRow {
    /// How the read model built its `tasks` before they left it: every task block of a snapshot in
    /// its order, with its file's links. The oracle the queries are compared with.
    static func legacy(snapshot: IndexSnapshot) -> [TaskRow] {
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        return snapshot.blocks.filter { $0.kind == "task" }.map { TaskRow(row: $0, links: links[$0.file] ?? []) }
    }

    /// The old `projects` field over those rows.
    static func legacyProjects(_ rows: [TaskRow]) -> [String] { VaultIndex.projectNames(rows.compactMap(\.project)) }
}

extension VaultReadModel {
    /// Everything the incremental tests compare: the screen fields, the counts and the fragments.
    func matchesFullBuild(_ other: VaultReadModel) -> Bool {
        matchesScreenFields(other) && counts.key == other.counts.key && fragments == other.fragments
    }
}

extension IndexCounts {
    /// Every count, for equality.
    var key: String {
        "\(filesByKind.sorted { $0.key < $1.key })|\(events)|\(tasks)|\(entities)|\(links)|\(unresolvedLinks)"
    }
}

/// How the read model built its goal fields before they left it (`VaultReadModel.rederive`), from
/// a snapshot in path order: the valid definitions by name, the resolved file of every file's
/// first place link, every definition's key (valid or not), the logs from 399 days before `today`
/// through 6 days after it (a key whose logs all fall outside kept an empty list), and every log
/// of each key. The oracle the goal queries are compared with.
struct LegacyGoalFields {
    let goals: [GoalDefinition]
    let goalPlaceFiles: [String: String]
    let reservedGoalKeys: Set<String>
    let goalLogs: [String: [GoalLog]]
    let allLogs: [String: [GoalLog]]

    init(snapshot: IndexSnapshot, today: CalendarDate) {
        var places: [String: IndexedLink] = [:]
        for link in snapshot.links where link.key == "place" && places[link.file] == nil { places[link.file] = link }
        goalPlaceFiles = places.compactMapValues(\.resolvedFile)
        goals = snapshot.entities.compactMap { GoalDefinition(entity: $0, place: places[$0.file]?.target) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        reservedGoalKeys = Set(snapshot.entities.compactMap(\.goalKey))
        allLogs = Dictionary(grouping: snapshot.goalLogs, by: \.key).mapValues { $0.compactMap(GoalLog.init(indexed:)) }
        let start = today.addingDays(-399) ?? today
        let end = today.addingDays(6) ?? today
        goalLogs = allLogs.mapValues { $0.filter { $0.day >= start && $0.day <= end } }
    }

    /// From a fresh index of the vault at `root`: the files on disk, as the store's index has them.
    init(root: URL, today: CalendarDate) throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        self.init(snapshot: try index.snapshot(), today: today)
    }

    /// How the read model built `goalStatuses` before the screens moved to the goal-status query:
    /// every indexed log of each valid definition, in path order, folded by `GoalProgress` on
    /// `today`. Keyed by goal key; a copied definition with the same key keeps the first by name,
    /// as the day page counted it.
    func goalStatuses(today: CalendarDate) -> [String: GoalStatus] {
        Dictionary(
            goals.map { ($0.key, GoalProgress.compute(definition: $0, logs: allLogs[$0.key] ?? [], today: today)) },
            uniquingKeysWith: { first, _ in first })
    }

    /// Statuses from the goal-log list (the window above), as the day page and "Close the day"
    /// counted them before the query: a copied key counts as the first by name.
    func windowStatuses(on day: CalendarDate) -> [String: GoalStatus] {
        Dictionary(
            goals.map { ($0.key, GoalProgress.compute(definition: $0, logs: goalLogs[$0.key] ?? [], today: day)) },
            uniquingKeysWith: { first, _ in first })
    }

    /// The goal-log list without the keys it kept empty: what a log query over the window answers.
    var windowLogs: [String: [GoalLog]] { goalLogs.filter { !$0.value.isEmpty } }

    /// What the daily reminder planned from: every definition and the goal-log list.
    var notificationGoals: NotificationGoals { NotificationGoals(definitions: goals, logs: goalLogs) }
}
