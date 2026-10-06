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
        previousContent: VaultReadModel = .empty
    ) async throws -> IndexUpdate {
        try await Task.detached {
            let result = try rebuild ? index.rebuild(vaultRoot: root) : index.refresh(vaultRoot: root)
            let types = EntityTypeReader.read(vaultRoot: root)
            let pathsChanged =
                !result.addedPaths.isEmpty || !result.updatedPaths.isEmpty || !result.deletedPaths.isEmpty
            let skippedChanged = result.skippedPaths != previousSkipped
            // Rebuild must always publish: an emptied vault reports no path deltas.
            if skipUnchanged && !rebuild && !pathsChanged && !skippedChanged && sameCatalog(types, previousTypes) {
                return IndexUpdate(
                    content: .empty, counts: IndexCounts(), skippedPaths: result.skippedPaths, hasChanges: false)
            }
            // Type catalog changes rebuild every file classification; always take the full path.
            let typeChanged = !sameCatalog(types, previousTypes)
            // Empty path deltas still publish for skipped-path or post-error retries. The index may
            // already include files the previous model never loaded — reconcile with a full build.
            let published = try VaultPublishedContent.applying(
                previous: previousContent, index: index, result: result,
                forceFull: rebuild || typeChanged || !previousContent.isBuilt || !pathsChanged)
            return IndexUpdate(
                content: published.content, counts: published.counts,
                skippedPaths: result.skippedPaths, hasChanges: true)
        }.value
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
