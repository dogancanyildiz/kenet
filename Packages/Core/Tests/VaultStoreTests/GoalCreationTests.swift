import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultStore

/// One `goals/creation/cases.json` record: the definition the user enters and the exact new file.
struct GoalCreationCase: Decodable, Sendable, CustomTestStringConvertible {
    let input: String
    let expected: String
    let name: String
    let period: String
    let kind: String
    /// Absent for milestones: they have no amount, so the store gets the API's placeholder 1.
    let target: Double?
    let unit: String?

    var testDescription: String { name }

    static let directory = "goals/creation/"

    static func all() throws -> [GoalCreationCase] {
        try JSONDecoder().decode(
            [GoalCreationCase].self,
            from: Data(contentsOf: Fixtures.root().appendingPathComponent(directory + "cases.json")))
    }
}

struct GoalCreationTests {
    @Test(arguments: try GoalCreationCase.all())
    func newDefinitionBytesMatchPortableFixturesAndRebuild(_ item: GoalCreationCase) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let directory = try Fixtures.root().appendingPathComponent(GoalCreationCase.directory)
        let input = try Data(contentsOf: directory.appendingPathComponent(item.input))
        #expect(Data(RawDocument(bytes: input).serialized()) == input)
        let period = try #require(GoalPeriod(rawValue: item.period))
        let kind = try #require(GoalKind(rawValue: item.kind))
        let path = try await vault.store.creatingGoal(
            name: item.name, period: period, kind: kind, target: item.target ?? 1, unit: item.unit)
        let expected = try Data(contentsOf: directory.appendingPathComponent(item.expected))
        #expect(path == "goals/\(item.name).md")
        #expect(try vault.bytes(path) == expected)
        #expect(Data(RawDocument(bytes: expected).serialized()) == expected)
        let definition = try #require(try vault.index.goalDefinitions().first)
        #expect(definition.name == item.name && definition.period == period && definition.kind == kind)
        #expect(definition.unit == item.unit)
        if let target = item.target { #expect(definition.target == target) }
        try vault.check()
    }

    @Test func everyExpectedCreationFileHasACase() throws {
        let directory = try Fixtures.root().appendingPathComponent(GoalCreationCase.directory)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix("-expected.md") }
        #expect(Set(files) == Set(try GoalCreationCase.all().map(\.expected)))
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
