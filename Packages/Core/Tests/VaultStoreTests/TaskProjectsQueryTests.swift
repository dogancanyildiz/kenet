import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

/// The task screens' project names against the construction they replaced in the app: the read
/// model's task rows by file and line, folded by `VaultIndex.projectNames`.
struct TaskProjectsQueryTests {
    @Test func sampleAndSyntheticVaultsMatchTheTaskRowConstruction() throws {
        let sample = try VaultIndex()
        try sample.rebuild(vaultRoot: Fixtures.root().appendingPathComponent("vaults/sample"))
        try expectConstruction(sample)
        #expect(try sample.taskProjects().isEmpty == false)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try SyntheticVault.generate(at: root, configuration: .compact)
        let synthetic = try VaultIndex()
        try synthetic.rebuild(vaultRoot: root)
        try expectConstruction(synthetic)
    }

    /// Done and cancelled tasks name projects too; of a precomposed and a decomposed spelling the
    /// one written first stays, whatever their byte order.
    @Test func edgeCaseVaultAnswersByHand() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try Self.writeEdgeCases(vault)
        try vault.index.rebuild(vaultRoot: vault.root)
        try expectConstruction(vault.index)
        let names = try vault.index.taskProjects()
        #expect(names == ["Bitmiş", "Café", "Ev", "İptal"])
        // Swift `==` is canonical; the scalars tell the written spelling apart.
        #expect(Array(names[1].unicodeScalars) == Array("Caf\u{E9}".unicodeScalars))

        // The only open task of a project completed: the project stays.
        let path = "journal/2026-03-01.md"
        let open = try #require(
            RawDocument(bytes: try vault.bytes(path)).bodyLines.tasks.first { $0.text.hasPrefix("açık") })
        try await vault.store.changingStatus(
            of: open, at: path, to: .done, completionDate: CalendarDate("2026-03-01")!)
        try expectConstruction(vault.index)
        #expect(try vault.index.taskProjects() == names)

        // The precomposed spelling's file gone: the decomposed one is the name now.
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent(path))
        try vault.index.refresh(vaultRoot: vault.root)
        try expectConstruction(vault.index)
        let after = try vault.index.taskProjects()
        #expect(after == ["Café", "Ev"])
        #expect(Array(after[0].unicodeScalars) == Array("Cafe\u{301}".unicodeScalars))

        // A new spelling of a known key that sorts first takes its place.
        try await vault.store.addingTask(on: CalendarDate("2026-03-05")!, text: "yeni", project: "EV")
        try expectConstruction(vault.index)
        #expect(try vault.index.taskProjects() == ["Café", "EV"])
    }

    static func writeEdgeCases(_ vault: StoreVault) throws {
        try vault.write(
            "journal/2026-03-01.md",
            "## Tasks\n- [x] bitti #project/Bitmiş\n- [-] iptal #project/İptal\n- [ ] açık #project/Caf\u{E9}\n")
        try vault.write(
            "notes/Ev.md",
            "- [ ] ayrışık #project/Cafe\u{301}\n- [ ] küçük #project/ev\n- [ ] büyük #project/Ev\n- [ ] projesiz\n")
        try vault.write("journal/2026-03-02.md", "## Tasks\n- [ ] yine #project/Ev\n")
    }

    /// The old construction over a fresh snapshot equals the query, scalar for scalar.
    private func expectConstruction(_ index: VaultIndex) throws {
        let snapshot = try index.snapshot()
        let rows = snapshot.blocks.filter { $0.kind == "task" }.sorted {
            $0.file != $1.file ? $0.file < $1.file : $0.ordinal < $1.ordinal
        }
        let expected = VaultIndex.projectNames(rows.compactMap(\.project))
        let names = try index.taskProjects()
        #expect(names.map { Array($0.unicodeScalars) } == expected.map { Array($0.unicodeScalars) })
    }
}
