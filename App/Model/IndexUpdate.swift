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
        skipUnchanged: Bool, previousSkipped: [SkippedPath]
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
            let snapshot = try index.snapshot()
            return IndexUpdate(
                content: VaultReadModel(snapshot: snapshot), counts: IndexCounts(snapshot: snapshot),
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
