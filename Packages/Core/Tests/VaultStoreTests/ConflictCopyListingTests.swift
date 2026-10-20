import Foundation
import Testing

@testable import VaultIndex
@testable import VaultStore

/// The names a day copy merge writes under `conflicts/` are the names Diagnostics lists: the
/// writer (`VaultStore`, `ConflictStamp`) and the reader (`ConflictCopyName`) keep one rule.
struct ConflictCopyListingTests {
    @Test func everyMergedConflictCopyIsListedWithItsDayFile() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let store = vault.store()
        var written: [String: String] = [:]
        for copy in try vault.index.refresh(vaultRoot: vault.root).dayCopies {
            let outcome = try await store.mergingDayCopy(copy)
            for path in outcome.conflictPaths { written[path] = outcome.dayPath }
        }
        #expect(written.keys.contains { $0.hasSuffix(" 2).md") }, "a numbered name is among the written ones")
        let listed = try VaultIndex.conflictCopies(vaultRoot: vault.root)
        for (path, dayPath) in written {
            #expect(listed.first { $0.copy == path }?.original == dayPath, "\(path)")
        }
    }

    /// Any whole-second time in four-digit years, and every number the writer tries, reads back.
    @Test func everyStampAndNumberTheWriterMakesIsAName() {
        var generator = SystemRandomNumberGenerator()
        let times =
            [0, 86_399, 951_782_400, 1_790_939_133, 253_402_300_799]
            + (0..<500).map { _ in Int.random(in: 0...253_402_300_799, using: &generator) }
        for time in times {
            let stem = "conflicts/2026-10-02 (conflict " + ConflictStamp.utc(time)
            #expect(ConflictCopyName.isConflictCopy(path: stem + ").md"), "\(time)")
            #expect(ConflictCopyName.isConflictCopy(path: stem + " 2).md"), "\(time)")
            #expect(ConflictCopyName.isConflictCopy(path: stem + " 1000).md"), "\(time)")
        }
    }
}
