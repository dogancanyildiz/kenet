import Foundation
import GoalTracking
import VaultFormat
import VaultIndex

/// Immutable screen data published together with the index counts.
///
/// Source of truth is `fragments` keyed by vault-relative path. Public lists (entities, goals)
/// are derived so a later screen can query Core directly without changing the fragment map. The
/// graph, the entity timelines, the days, the goal statuses, the tasks and the project names
/// already do (`IndexStore.computeGraphInput`, `computeEntityTimeline(for:)`,
/// `computeLastEncounters(asOf:)`, `computeDaySummaries(from:to:)`, `computeDay(on:)`,
/// `computeGoalStatuses(today:)`, the task queries, `computeProjects()`); the notification
/// planner reads its tasks and written days through `computeNotificationDays(from:through:)`.
struct VaultReadModel: Sendable {
    /// Per-file index slices. An empty map after a successful build is a valid empty vault.
    private(set) var fragments: [String: VaultFileFragment] = [:]
    /// False only for the never-published `.empty` sentinel (and skipped refresh placeholders).
    private(set) var isBuilt = false
    /// Set when an incremental publish could not load a reported path, or when a write published
    /// incompletely. The next `VaultPublishedContent.applying` takes the full path.
    private(set) var needsFullReconcile = false
    /// Calendar day used for the last `rederive` / goal-log patch. Day rollover forces rederive.
    private(set) var derivedForDay: CalendarDate?

    var goals: [GoalDefinition] = []
    var goalPlaceFiles: [String: String] = [:]
    var goalLogs: [String: [GoalLog]] = [:]
    var reservedGoalKeys: Set<String> = []
    var goalLogStart = LocalDay.today().addingDays(-399)!
    var entities: [EntitySummary] = []
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

        if try reloadFragments(reload, index: index) {
            needsFullReconcile = true
        }
        // Estimated paths that never appear in the index under that spelling need a full rebuild.
        for path in estimatedPaths where !deletedPaths.contains(path) && fragments[path] == nil {
            needsFullReconcile = true
        }
        if needsFullReconcile { return }

        // Newly resolvable incoming links on other files. Block identifier ownership no longer
        // reaches a fragment: it named task rows, which the task queries read from the index.
        var collateral = Set<String>()
        for path in reload {
            collateral.formUnion(try index.links(to: path).map(\.file))
        }
        collateral.subtract(deletedPaths)
        collateral.subtract(reload)
        for path in collateral where before[path] == nil {
            if let fragment = fragments[path] { before[path] = fragment }
        }
        if !collateral.isEmpty {
            if try reloadFragments(collateral, index: index) {
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

    private mutating func reloadFragments(_ paths: Set<String>, index: VaultIndex) throws -> Bool {
        var missed = false
        for path in paths {
            if let fragment = try index.loadFragment(path: path) {
                fragments[path] = fragment
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
        // Path order, as a snapshot of the fragments lists its rows.
        let ordered = fragments.keys.sorted().map { fragments[$0]! }
        let entityRows = ordered.compactMap(\.entity)
        var places: [String: IndexedLink] = [:]
        for fragment in ordered {
            if let place = fragment.links.first(where: { $0.key == "place" }) { places[fragment.file.path] = place }
        }
        goalPlaceFiles = places.compactMapValues(\.resolvedFile)
        goals = entityRows.compactMap { GoalDefinition(entity: $0, place: places[$0.file]?.target) }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        let indexedLogs = ordered.flatMap(\.goalLogs)
        reservedGoalKeys = Set(entityRows.compactMap(\.goalKey) + indexedLogs.map(\.key))
        let allLogs = Dictionary(grouping: indexedLogs, by: \.key).mapValues {
            $0.compactMap(GoalLog.init(indexed:))
        }
        // Near-future corrections must also suppress the upcoming notification window.
        let goalLogEnd = today.addingDays(6) ?? today
        goalLogs = allLogs.mapValues { $0.filter { $0.day >= goalLogStart && $0.day <= goalLogEnd } }
        var incoming: [String: Int] = [:]
        counts = IndexCounts()
        for fragment in ordered {
            counts.filesByKind[fragment.file.kind, default: 0] += 1
            counts.events += fragment.eventCount
            counts.tasks += fragment.taskCount
            counts.links += fragment.links.count
            for link in fragment.links {
                if let target = link.resolvedFile {
                    incoming[target, default: 0] += 1
                } else {
                    counts.unresolvedLinks += 1
                }
            }
        }
        counts.entities = entityRows.count
        entities = ordered.compactMap { fragment -> EntitySummary? in
            guard let entity = fragment.entity, entity.kind != "goal" else { return nil }
            return EntitySummary(
                id: entity.file, kind: entity.kind, name: entity.name, qualifier: entity.qualifier,
                aliases: fragment.aliases.sorted { $0.ordinal < $1.ordinal }.map(\.name),
                incomingLinks: incoming[entity.file] ?? 0)
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            let qualifier = ($0.qualifier ?? "").localizedStandardCompare($1.qualifier ?? "")
            return qualifier == .orderedSame ? $0.id < $1.id : qualifier == .orderedAscending
        }
    }

    /// Screen-visible equality used by incremental vs full-build tests.
    func matchesScreenFields(_ other: VaultReadModel) -> Bool {
        goals == other.goals
            && goalPlaceFiles == other.goalPlaceFiles
            && goalLogs == other.goalLogs
            && reservedGoalKeys == other.reservedGoalKeys
            && goalLogStart == other.goalLogStart
            && entities == other.entities
    }

    static func debugDiff(_ left: VaultReadModel, _ right: VaultReadModel) -> String {
        var lines: [String] = []
        if left.goals != right.goals { lines.append("goals") }
        if left.goalPlaceFiles != right.goalPlaceFiles { lines.append("goalPlaceFiles") }
        if left.goalLogs != right.goalLogs { lines.append("goalLogs") }
        if left.reservedGoalKeys != right.reservedGoalKeys { lines.append("reservedGoalKeys") }
        if left.goalLogStart != right.goalLogStart { lines.append("goalLogStart") }
        if left.entities != right.entities { lines.append("entities") }
        return "diff: " + (lines.isEmpty ? "none" : lines.joined(separator: ", "))
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
