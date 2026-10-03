import Foundation
import VaultIndex

struct IndexUpdate: Sendable {
    let counts: IndexCounts
    let skippedPaths: [SkippedPath]

    static func read(index: VaultIndex, root: URL, rebuild: Bool) async throws -> IndexUpdate {
        try await Task.detached {
            let result = try rebuild ? index.rebuild(vaultRoot: root) : index.refresh(vaultRoot: root)
            return IndexUpdate(counts: IndexCounts(snapshot: try index.snapshot()), skippedPaths: result.skippedPaths)
        }.value
    }
}
