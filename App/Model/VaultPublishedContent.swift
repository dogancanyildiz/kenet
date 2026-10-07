import Foundation
import VaultFormat
import VaultIndex

/// Snapshot-derived screen model and counts, built together so write and refresh share one path.
struct VaultPublishedContent: Sendable {
    let content: VaultReadModel
    let counts: IndexCounts

    /// Test seam: wraps read-model construction. The probe must run `body` exactly once and return
    /// its result. `kind` is `"full"` or `"incremental"` so suites can ignore unrelated builds.
    nonisolated(unsafe) static var buildProbe:
        (@Sendable (_ kind: String, _ body: () throws -> VaultPublishedContent) throws -> VaultPublishedContent)?

    static func from(snapshot: IndexSnapshot, today: CalendarDate = LocalDay.today()) -> VaultPublishedContent {
        let build = { () throws -> VaultPublishedContent in
            let content = VaultReadModel(snapshot: snapshot, today: today)
            return VaultPublishedContent(content: content, counts: content.counts)
        }
        if let buildProbe {
            do { return try buildProbe("full", build) } catch {
                return (try? build()) ?? VaultPublishedContent(content: .empty, counts: IndexCounts())
            }
        }
        return (try? build()) ?? VaultPublishedContent(content: .empty, counts: IndexCounts())
    }

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
        if let buildProbe {
            return try buildProbe(kind, body)
        }
        return try body()
    }
}
