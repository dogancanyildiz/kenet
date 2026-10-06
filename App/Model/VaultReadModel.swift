import Foundation
import GoalTracking
import VaultFormat
import VaultIndex

/// Immutable screen data published together with the index counts.
///
/// Source of truth is `fragments` keyed by vault-relative path. Public lists (days, tasks,
/// entities, graph, timelines, goals) are derived so a later screen can query Core directly
/// without changing the fragment map.
struct VaultReadModel: Sendable {
    /// Per-file index slices. An empty map after a successful build is a valid empty vault.
    private(set) var fragments: [String: VaultFileFragment] = [:]
    /// False only for the never-published `.empty` sentinel (and skipped refresh placeholders).
    private(set) var isBuilt = false
    /// Set when an incremental publish could not load a reported path, or when a write published
    /// incompletely. The next `VaultPublishedContent.applying` takes the full path.
    private(set) var needsFullReconcile = false
    /// Calendar day used for the last `rederive` / goal-status patch. Day rollover forces rederive.
    private(set) var derivedForDay: CalendarDate?

    var goals: [GoalDefinition] = []
    var goalPlaceFiles: [String: String] = [:]
    var goalLogs: [String: [GoalLog]] = [:]
    var reservedGoalKeys: Set<String> = []
    var goalLogStart = LocalDay.today().addingDays(-399)!
    var goalStatuses: [String: GoalStatus] = [:]
    var tasks: [TaskRow] = []
    var projects: [String] { VaultIndex.projectNames(tasks.compactMap(\.project)) }
    var days: [DaySummary] = []
    var entities: [EntitySummary] = []
    var graphInput = GraphInput()
    var entityTimeline: [String: [EntityTimelineDay]] = [:]
    /// Kept in sync with fragments so publishes need not recount the whole vault.
    var counts = IndexCounts()

    static let empty = VaultReadModel()

    init() {}

    init(snapshot: IndexSnapshot, today: CalendarDate = LocalDay.today()) {
        fragments = Self.fragments(from: snapshot)
        isBuilt = true
        rederive(today: today)
    }

    /// Full rebuild from the live index (first open, type catalog change, or empty previous).
    init(index: VaultIndex, today: CalendarDate = LocalDay.today()) throws {
        self.init(snapshot: try index.snapshot(), today: today)
    }

    mutating func markNeedsFullReconcile() {
        needsFullReconcile = true
    }

    /// Replaces fragments for changed paths, drops deleted paths, then rederives screen fields.
    /// Link-resolution and identifier-ownership side effects reload additional paths as needed.
    mutating func apply(
        changedPaths: Set<String>, deletedPaths: Set<String>, index: VaultIndex,
        estimatedPaths: Set<String> = [], today: CalendarDate = LocalDay.today()
    ) throws {
        var reload = changedPaths
        reload.subtract(deletedPaths)

        var identifiers = Set(
            deletedPaths.flatMap { fragments[$0]?.blocks.compactMap(\.identifier) ?? [] })
        identifiers.formUnion(reload.flatMap { fragments[$0]?.blocks.compactMap(\.identifier) ?? [] })

        // Sources that previously resolved to a deleted file must pick up NULL resolvedFile.
        for path in deletedPaths {
            for (source, fragment) in fragments where fragment.links.contains(where: { $0.resolvedFile == path }) {
                reload.insert(source)
            }
        }

        var before: [String: VaultFileFragment] = [:]
        for path in reload.union(deletedPaths) {
            if let fragment = fragments[path] { before[path] = fragment }
        }

        for path in deletedPaths {
            fragments.removeValue(forKey: path)
        }
        isBuilt = true

        if try reloadFragments(reload, index: index, identifiers: &identifiers) {
            needsFullReconcile = true
        }
        // Estimated paths that never appear in the index under that spelling need a full rebuild.
        for path in estimatedPaths where !deletedPaths.contains(path) && fragments[path] == nil {
            needsFullReconcile = true
        }
        if needsFullReconcile { return }

        // Newly resolvable incoming links and ownership flips on other files.
        var collateral = Set<String>()
        for path in reload {
            collateral.formUnion(try index.links(to: path).map(\.file))
        }
        for identifier in identifiers {
            if let owner = try index.owner(of: identifier) { collateral.insert(owner.file) }
            for (file, fragment) in fragments
            where fragment.blocks.contains(where: { $0.identifier == identifier }) {
                collateral.insert(file)
            }
        }
        collateral.subtract(deletedPaths)
        collateral.subtract(reload)
        for path in collateral where before[path] == nil {
            if let fragment = fragments[path] { before[path] = fragment }
        }
        if !collateral.isEmpty {
            if try reloadFragments(collateral, index: index, identifiers: &identifiers) {
                needsFullReconcile = true
                return
            }
        }

        let touched = reload.union(collateral)
        if derivedForDay != today
            || requiresFullRederive(before: before, touched: touched, removed: deletedPaths)
        {
            rederive(today: today)
        } else {
            patchDerived(before: before, touched: touched, removed: deletedPaths, today: today)
        }
    }

    private mutating func reloadFragments(
        _ paths: Set<String>, index: VaultIndex, identifiers: inout Set<String>
    ) throws -> Bool {
        var missed = false
        for path in paths {
            if let fragment = try index.loadFragment(path: path) {
                fragments[path] = fragment
                identifiers.formUnion(fragment.blocks.compactMap(\.identifier))
            } else {
                fragments.removeValue(forKey: path)
                // Reported as changed but absent from the index under that path — guessed/wrong path.
                missed = true
            }
        }
        return missed
    }

    mutating func rederive(today: CalendarDate) {
        derivedForDay = today
        needsFullReconcile = false
        goalLogStart = today.addingDays(-399) ?? today
        let snapshot = asSnapshot()
        let goalPlaces = Dictionary(grouping: snapshot.links.filter { $0.key == "place" }, by: \.file)
        goalPlaceFiles = goalPlaces.compactMapValues { $0.first?.resolvedFile }
        goals = snapshot.entities.compactMap { GoalDefinition(entity: $0, place: goalPlaces[$0.file]?.first?.target) }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        reservedGoalKeys = Set(snapshot.entities.compactMap(\.goalKey) + snapshot.goalLogs.map(\.key))
        let allLogs = Dictionary(grouping: snapshot.goalLogs, by: \.key).mapValues {
            $0.compactMap(GoalLog.init(indexed:))
        }
        // Near-future corrections must also suppress the upcoming notification window.
        let goalLogEnd = today.addingDays(6) ?? today
        goalLogs = allLogs.mapValues { $0.filter { $0.day >= goalLogStart && $0.day <= goalLogEnd } }
        goalStatuses = [:]
        for goal in goals {
            goalStatuses[goal.key] = GoalProgress.compute(definition: goal, logs: allLogs[goal.key] ?? [], today: today)
        }
        entityTimeline = EntityTimeline.build(snapshot: snapshot)
        let goalFiles = Set(snapshot.goalLogs.map(\.file))
        let blocks = Dictionary(grouping: snapshot.blocks, by: \.file)
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        tasks = snapshot.blocks.filter { $0.kind == "task" }.map {
            TaskRow(row: $0, links: links[$0.file] ?? [])
        }
        let aliases = Dictionary(grouping: snapshot.aliases, by: \.file)
        let incoming = Dictionary(grouping: snapshot.links.compactMap(\.resolvedFile), by: { $0 })
        entities = snapshot.entities.filter { $0.kind != "goal" }.map { entity in
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
        graphInput = GraphInput(
            snapshot: snapshot, entities: entities.filter { ["person", "place"].contains($0.kind) })
        counts = IndexCounts(snapshot: snapshot)
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
            return DaySummary(
                id: file.path, date: date, events: events, journal: journal,
                hasGoalRecords: goalFiles.contains(file.path))
        }.sorted(by: Self.daySort)
    }

    /// Same ordering as a full snapshot derive: newest date first, path ascending on ties.
    static func daySort(_ left: DaySummary, _ right: DaySummary) -> Bool {
        if left.date != right.date { return left.date > right.date }
        return left.id < right.id
    }

    func day(on date: CalendarDate) -> DaySummary {
        days.first { $0.date == date }
            ?? DaySummary(id: "journal/\(date).md", date: date, events: [], journal: [])
    }

    /// Screen-visible equality used by incremental vs full-build tests.
    func matchesScreenFields(_ other: VaultReadModel) -> Bool {
        goals == other.goals
            && goalPlaceFiles == other.goalPlaceFiles
            && goalLogs == other.goalLogs
            && reservedGoalKeys == other.reservedGoalKeys
            && goalLogStart == other.goalLogStart
            && goalStatuses == other.goalStatuses
            && tasks.map(\.equalityKey) == other.tasks.map(\.equalityKey)
            && days.map(\.equalityKey) == other.days.map(\.equalityKey)
            && entities == other.entities
            && graphInput.equalityKey == other.graphInput.equalityKey
            && entityTimeline.mapValues { $0.map(\.equalityKey) }
                == other.entityTimeline.mapValues {
                    $0.map(\.equalityKey)
                }
    }

    static func debugDiff(_ left: VaultReadModel, _ right: VaultReadModel) -> String {
        var lines: [String] = []
        if left.goals != right.goals { lines.append("goals") }
        if left.goalPlaceFiles != right.goalPlaceFiles { lines.append("goalPlaceFiles") }
        if left.goalLogs != right.goalLogs { lines.append("goalLogs") }
        if left.reservedGoalKeys != right.reservedGoalKeys { lines.append("reservedGoalKeys") }
        if left.goalLogStart != right.goalLogStart { lines.append("goalLogStart") }
        if left.goalStatuses != right.goalStatuses { lines.append("goalStatuses") }
        if left.tasks.map(\.equalityKey) != right.tasks.map(\.equalityKey) {
            lines.append("tasks \(left.tasks.count)/\(right.tasks.count)")
        }
        if left.days.map(\.equalityKey) != right.days.map(\.equalityKey) {
            lines.append("days \(left.days.count)/\(right.days.count)")
        }
        if left.entities != right.entities { lines.append("entities") }
        if left.graphInput.equalityKey != right.graphInput.equalityKey { lines.append("graphInput") }
        let leftTimeline = left.entityTimeline.mapValues { $0.map(\.equalityKey) }
        let rightTimeline = right.entityTimeline.mapValues { $0.map(\.equalityKey) }
        if leftTimeline != rightTimeline { lines.append("entityTimeline") }
        return "diff: " + (lines.isEmpty ? "none" : lines.joined(separator: ", "))
    }

    func asSnapshot() -> IndexSnapshot {
        let paths = fragments.keys.sorted()
        return IndexSnapshot(
            files: paths.map { fragments[$0]!.file },
            entities: paths.compactMap { fragments[$0]!.entity },
            aliases: paths.flatMap { fragments[$0]!.aliases },
            blocks: paths.flatMap { fragments[$0]!.blocks },
            links: paths.flatMap { fragments[$0]!.links },
            goalLogs: paths.flatMap { fragments[$0]!.goalLogs })
    }

    private static func fragments(from snapshot: IndexSnapshot) -> [String: VaultFileFragment] {
        let entities = Dictionary(uniqueKeysWithValues: snapshot.entities.map { ($0.file, $0) })
        let aliases = Dictionary(grouping: snapshot.aliases, by: \.file)
        let blocks = Dictionary(grouping: snapshot.blocks, by: \.file)
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        let goalLogs = Dictionary(grouping: snapshot.goalLogs, by: \.file)
        var result: [String: VaultFileFragment] = [:]
        result.reserveCapacity(snapshot.files.count)
        for file in snapshot.files {
            result[file.path] = VaultFileFragment(
                file: file, entity: entities[file.path], aliases: aliases[file.path] ?? [],
                blocks: blocks[file.path] ?? [], links: links[file.path] ?? [],
                goalLogs: goalLogs[file.path] ?? [])
        }
        return result
    }
}

/// A source-ordered day and its read-only journal paragraphs.
struct DaySummary: Identifiable, Sendable {
    let id: String
    let date: CalendarDate
    let events: [EventRow]
    let journal: [JournalRow]
    var hasGoalRecords = false

    var preview: String? {
        journal.first { $0.headingLevel == nil }?.text.plainText.components(separatedBy: "\n").first
    }

    fileprivate var equalityKey: String {
        let eventKeys = events.map {
            "\($0.id)|\($0.time?.raw ?? "")|\($0.text.plainText)|\($0.sourceLine)|\($0.sourceEnd)|\($0.sourceText)|\($0.sourceIdentifier ?? "")|\($0.text.spanKey)"
        }.joined(separator: ";")
        let journalKeys = journal.map {
            "\($0.id)|\($0.headingLevel.map(String.init) ?? "")|\($0.text.plainText)|\($0.text.spanKey)"
        }.joined(separator: ";")
        return "\(id)|\(date)|\(hasGoalRecords)|\(eventKeys)|\(journalKeys)"
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

extension LinkedText {
    fileprivate var spanKey: String {
        spans.map { "\($0.text):\($0.destination ?? "")" }.joined(separator: ",")
    }
}

extension TaskRow {
    fileprivate var equalityKey: String {
        "\(id)|\(file)|\(text.plainText)|\(sourceLine)|\(sourceEnd)|\(sourceText)|\(sourceIdentifier ?? "")|\(rawStatus)|\(due?.description ?? "")|\(start?.description ?? "")|\(done?.description ?? "")|\(priority?.token ?? "")|\(project ?? "")|\(recurrenceSource ?? "")|\(linkedFiles.sorted().joined(separator: ","))|\(text.spanKey)"
    }
}

extension GraphInput {
    fileprivate var equalityKey: String {
        let entityKeys = entities.map { "\($0.id)|\($0.incomingLinks)" }.joined(separator: ";")
        let totalKeys = totals.keys.sorted().map { "\($0):\(totals[$0]!)" }.joined(separator: ",")
        let dayKeys = days.map { day in
            let mentions = day.mentions.keys.sorted().map { "\($0):\(day.mentions[$0]!)" }.joined(separator: ",")
            return "\(day.date)|\(mentions)"
        }.joined(separator: ";")
        return "\(entityKeys)|\(totalKeys)|\(dayKeys)"
    }
}

extension EntityTimelineDay {
    fileprivate var equalityKey: String {
        let rowKeys = rows.map {
            "\($0.file)|\($0.ordinal)|\($0.text.plainText)|\($0.text.spanKey)"
        }.joined(separator: ";")
        return "\(date)|\(rowKeys)"
    }
}
