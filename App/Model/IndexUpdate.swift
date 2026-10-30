import Foundation
import VaultFormat
import VaultIndex

struct IndexUpdate: Sendable {
    let content: VaultReadModel
    let counts: IndexCounts
    let skippedPaths: [SkippedPath]
    /// False when refresh found no Markdown path changes and the type catalog is unchanged.
    let hasChanges: Bool
    /// The scan's iCloud placeholders without their original and its day copies, as Core reports
    /// them (`RebuildResult`); after a directory update only those directories'. Filled even when
    /// nothing else changed: a placeholder is not a Markdown path change.
    var pendingDownloads: [String] = []
    var dayCopies: [String] = []

    static func read(
        index: VaultIndex, root: URL, rebuild: Bool, previousTypes: EntityTypeCatalog,
        skipUnchanged: Bool, previousSkipped: [SkippedPath],
        previousContent: VaultReadModel = .empty, directories: Set<String>? = nil,
        previousSync: SyncLists = SyncLists()
    ) async throws -> IndexUpdate {
        try await Task.detached {
            let result: RebuildResult
            var skipped: [SkippedPath]
            if let directories, !rebuild {
                // Only the notified subtrees are scanned; skipped paths elsewhere still stand. A type
                // change makes Core rebuild everything; its list then already holds the others.
                result = try index.update(paths: directories, vaultRoot: root)
                skipped =
                    previousSkipped.filter { !pathIsInside($0.path, directories) && !result.skippedPaths.contains($0) }
                    + result.skippedPaths
                // Core's own order, so an unchanged list compares equal.
                skipped.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
            } else {
                result = try rebuild ? index.rebuild(vaultRoot: root) : index.refresh(vaultRoot: root)
                skipped = result.skippedPaths
            }
            let sync = SyncLists(
                result: result, root: root, previous: previousSync, directories: rebuild ? nil : directories)
            let types = EntityTypeReader.read(vaultRoot: root)
            let pathsChanged =
                !result.addedPaths.isEmpty || !result.updatedPaths.isEmpty || !result.deletedPaths.isEmpty
            let skippedChanged = skipped != previousSkipped
            // Rebuild must always publish: an emptied vault reports no path deltas.
            // A reconcile flag also forces a publish even when Core reports no path deltas.
            if skipUnchanged && !rebuild && !pathsChanged && !skippedChanged && sameCatalog(types, previousTypes)
                && !previousContent.needsFullReconcile
            {
                return IndexUpdate(
                    content: .empty, counts: IndexCounts(), skippedPaths: skipped, hasChanges: false,
                    pendingDownloads: sync.pendingDownloads, dayCopies: sync.dayCopies)
            }
            // Type catalog changes rebuild every file classification; always take the full path.
            let typeChanged = !sameCatalog(types, previousTypes)
            // Empty path deltas still publish for skipped-path or post-error retries. The index may
            // already include files the previous model never loaded — reconcile with a full build.
            let published = try VaultPublishedContent.applying(
                previous: previousContent, index: index, result: result,
                forceFull: rebuild || typeChanged || !previousContent.isBuilt || !pathsChanged
                    || previousContent.needsFullReconcile)
            return IndexUpdate(
                content: published.content, counts: published.counts,
                skippedPaths: skipped, hasChanges: true,
                pendingDownloads: sync.pendingDownloads, dayCopies: sync.dayCopies)
        }.value
    }
}

/// A vault's iCloud placeholders without their original and its day copies, as one refresh leaves them.
struct SyncLists: Sendable, Equatable {
    var pendingDownloads: [String] = []
    var dayCopies: [String] = []

    /// The entity type catalog, which Core's Markdown scan does not report.
    static let typesPath = ".app/types.json"
}

extension SyncLists {
    /// `result`'s lists. A directory update scans only `directories`: the other directories' entries
    /// of `previous` still stand. The type catalog's placeholder is looked up on disk every time.
    init(result: RebuildResult, root: URL, previous: SyncLists, directories: Set<String>?) {
        var pending = result.pendingDownloads
        var copies = result.dayCopies
        if let directories {
            pending = Array(Set(previous.pendingDownloads.filter { !pathIsInside($0, directories) } + pending))
            copies = DayCopyName.copies(in: Set(previous.dayCopies.filter { !pathIsInside($0, directories) } + copies))
        }
        pending.removeAll { $0 == Self.typesPath }
        let app = root.appendingPathComponent(".app", isDirectory: true)
        if !FileManager.default.fileExists(atPath: app.appendingPathComponent("types.json").path),
            FileManager.default.fileExists(
                atPath: app.appendingPathComponent(PlaceholderName.placeholderName(for: "types.json")).path)
        {
            pending.append(Self.typesPath)
        }
        pendingDownloads = pending.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        dayCopies = copies
    }
}

/// Whether `path` lies in one of `directories` (vault-relative), compared as the index compares:
/// by the vault's name key (`nameComparisonKey`), so `people/IŞIK` holds `people/Işık/a.md`.
func pathIsInside(_ path: String, _ directories: Set<String>) -> Bool {
    let file = nameComparisonKey(path)
    return directories.contains { directory in
        let prefix = nameComparisonKey(directory)
        return prefix.isEmpty || file == prefix || file.hasPrefix(prefix + "/")
    }
}

private func sameCatalog(_ left: EntityTypeCatalog, _ right: EntityTypeCatalog) -> Bool {
    left.types == right.types && sameIssue(left.issue, right.issue)
}

private func sameIssue(_ left: EntityTypeCatalog.Issue?, _ right: EntityTypeCatalog.Issue?) -> Bool {
    switch (left, right) {
    case (nil, nil), (.invalid, .invalid), (.unreadable, .unreadable): return true
    default: return false
    }
}
