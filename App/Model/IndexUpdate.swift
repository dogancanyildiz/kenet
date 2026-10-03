import Foundation
import VaultIndex

struct IndexUpdate: Sendable {
    let content: VaultReadModel
    let counts: IndexCounts
    let skippedPaths: [SkippedPath]

    static func read(index: VaultIndex, root: URL, rebuild: Bool) async throws -> IndexUpdate {
        try await Task.detached {
            let result = try rebuild ? index.rebuild(vaultRoot: root) : index.refresh(vaultRoot: root)
            let snapshot = try index.snapshot()
            return IndexUpdate(
                content: VaultReadModel(snapshot: snapshot), counts: IndexCounts(snapshot: snapshot),
                skippedPaths: result.skippedPaths)
        }.value
    }
}
