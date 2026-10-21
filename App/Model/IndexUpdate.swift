import Foundation
import VaultFormat
import VaultIndex

struct IndexUpdate: Sendable {
    let content: VaultReadModel
    let counts: IndexCounts
    let skippedPaths: [SkippedPath]
    /// False when refresh found no Markdown path changes and the type catalog is unchanged.
    let hasChanges: Bool

    static func read(
        index: VaultIndex, root: URL, rebuild: Bool, previousTypes: EntityTypeCatalog,
        skipUnchanged: Bool, previousSkipped: [SkippedPath],
        previousContent: VaultReadModel = .empty, directories: Set<String>? = nil
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
                    content: .empty, counts: IndexCounts(), skippedPaths: skipped, hasChanges: false)
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
                skippedPaths: skipped, hasChanges: true)
        }.value
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
