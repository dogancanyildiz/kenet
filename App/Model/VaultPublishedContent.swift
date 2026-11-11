import Foundation
import Synchronization
import VaultFormat
import VaultIndex

/// Snapshot-derived screen model and counts, built together so write and refresh share one path.
struct VaultPublishedContent: Sendable {
    let content: VaultReadModel
    let counts: IndexCounts

    typealias BuildProbe =
        @Sendable (_ kind: String, _ body: () throws -> VaultPublishedContent) throws -> VaultPublishedContent

    /// Test seam: wraps read-model construction. The probe must run `body` exactly once and return
    /// its result. `kind` is `"full"` or `"incremental"` so suites can ignore unrelated builds.
    /// Builds run in detached tasks, which a task-local value does not reach; a lock guards it instead.
    static var buildProbe: BuildProbe? {
        get { probe.withLock { $0 } }
        set { probe.withLock { $0 = newValue } }
    }
    private static let probe = Mutex<BuildProbe?>(nil)

    static func load(from index: VaultIndex, today: CalendarDate = LocalDay.today()) throws -> VaultPublishedContent {
        try runThrowingBuild(kind: "full") {
            let content = try VaultReadModel(index: index, today: today)
            return VaultPublishedContent(content: content, counts: content.counts)
        }
    }

    /// Incremental path shared by writes and refresh. Falls back to a full load when needed.
    static func applying(
        previous: VaultReadModel, index: VaultIndex, changedPaths: Set<String>,
        deletedPaths: Set<String> = [], forceFull: Bool = false,
        estimatedPaths: Set<String> = [], today: CalendarDate = LocalDay.today()
    ) throws -> VaultPublishedContent {
        if forceFull || !previous.isBuilt || previous.needsFullReconcile {
            return try load(from: index, today: today)
        }
        let incremental = try runThrowingBuild(kind: "incremental") {
            var content = previous
            try content.apply(
                changedPaths: changedPaths, deletedPaths: deletedPaths, index: index,
                estimatedPaths: estimatedPaths, today: today)
            return VaultPublishedContent(content: content, counts: content.counts)
        }
        // Missed fragment loads (guessed paths) force a full reconcile in the same publish.
        if incremental.content.needsFullReconcile {
            return try load(from: index, today: today)
        }
        return incremental
    }

    /// Applies a Core rebuild/refresh delta to the previous model.
    static func applying(
        previous: VaultReadModel, index: VaultIndex, result: RebuildResult, forceFull: Bool = false,
        today: CalendarDate = LocalDay.today()
    ) throws -> VaultPublishedContent {
        let changed = Set(result.addedPaths).union(result.updatedPaths)
        return try applying(
            previous: previous, index: index, changedPaths: changed,
            deletedPaths: Set(result.deletedPaths), forceFull: forceFull, today: today)
    }

    private static func runThrowingBuild(
        kind: String, _ body: () throws -> VaultPublishedContent
    ) throws -> VaultPublishedContent {
        if let probe = buildProbe {
            return try probe(kind, body)
        }
        return try body()
    }
}
