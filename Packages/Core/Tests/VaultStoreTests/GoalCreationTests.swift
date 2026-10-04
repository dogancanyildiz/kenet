import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultStore

struct GoalCreationTests {
    @Test func newDefinitionBytesMatchPortableFixturesAndRebuild() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let input = try Data(contentsOf: Fixtures.root().appendingPathComponent("goals/creation/input.md"))
        #expect(Data(RawDocument(bytes: input).serialized()) == input)
        let first = try await vault.store.creatingGoal(name: "Su İçme", period: .day, kind: .boolean, target: 1)
        let second = try await vault.store.creatingGoal(
            name: "Sayfa", period: .year, kind: .number, target: 240, unit: "sayfa")
        for (path, fixture) in [(first, "boolean-expected.md"), (second, "number-expected.md")] {
            let expected = try Data(contentsOf: Fixtures.root().appendingPathComponent("goals/creation/" + fixture))
            #expect(try vault.bytes(path) == expected)
            #expect(Data(RawDocument(bytes: expected).serialized()) == expected)
        }
        #expect(first == "goals/Su İçme.md")
        #expect(try vault.index.goalDefinitions().count == 2)
        try vault.check()
    }

    @Test func currentDiskKeysInvalidDefinitionsAndOrphanLogsAreReserved() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        // No refresh: reservations must see external edits before the watcher does.
        try vault.write("goals/Other.md", "---\ntype: goal\nname: Other\nkey: su-icme\nperiod: invalid\n---\n")
        try vault.write(storePath, "---\ntype: journal\ndate: 2026-09-27\ngoals:\n  su-icme-2: true\n---\n")
        let path = try await vault.store.creatingGoal(name: "Su İçme", period: .week, kind: .boolean, target: 3)
        #expect(String(decoding: try vault.bytes(path), as: UTF8.self).contains("key: su-icme-3\n"))
        _ = try vault.index.refresh(vaultRoot: vault.root)
        try vault.check()
    }

    @Test func diskDisplayNameAndFilenameCollisionsNeverOverwrite() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let source = "---\ntype: goal\nname: Spor\nkey: active\nperiod: week\nkind: boolean\ntarget: 3\n---\nKeep\n"
        try vault.write("goals/Old filename.md", source)
        await #expect(throws: VaultStoreError.nameTaken) {
            try await vault.store.creatingGoal(name: "SPOR", period: .day, kind: .boolean, target: 1)
        }
        #expect(try vault.bytes("goals/Old filename.md") == Data(source.utf8))
        try vault.write("notes/READ.md", "keep")
        await #expect(throws: VaultStoreError.nameTaken) {
            try await vault.store.creatingGoal(name: "Read", period: .day, kind: .number, target: 20)
        }
    }

    @Test func concurrentCreationUsesUniqueKeysAndRejectsInvalidAmounts() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        async let first = vault.store.creatingGoal(name: "Su İçme", period: .day, kind: .boolean, target: 1)
        async let second = vault.store.creatingGoal(name: "Su-İçme", period: .day, kind: .boolean, target: 1)
        _ = try await (first, second)
        #expect(Set(try vault.index.goalDefinitions().map(\.key)) == ["su-icme", "su-icme-2"])
        for amount in [0, -1, Double.infinity, Double.nan] {
            await #expect(throws: EditError.invalidValue) {
                try await vault.store.creatingGoal(name: "Invalid", period: .day, kind: .number, target: amount)
            }
        }
        let tiny = try await vault.store.creatingGoal(name: "Tiny", period: .day, kind: .number, target: 1e-8)
        #expect(String(decoding: try vault.bytes(tiny), as: UTF8.self).contains("target: 0.00000001"))
        try vault.check()
    }
}
