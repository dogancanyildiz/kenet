import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

struct DefinitionDeletionTests {
    @Test(arguments: [VaultEntityKind.person, .place, .custom("book")])
    func entityDeletionPreservesJournalAndConflictAndReleasesName(_ kind: VaultEntityKind) async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        if case .custom = kind {
            let catalog = EntityTypeReader.read(vaultRoot: try Fixtures.root().appendingPathComponent("vaults/typed"))
            try await vault.store.savingEntityType(try #require(catalog.types.first))
        }
        let path = try await vault.store.creatingEntity(kind: kind, name: "Kurgusal Varlık")
        _ = try await vault.store.addingEvent(on: storeDate, text: "[[Kurgusal Varlık]]")
        let definition = try vault.bytes(path)
        try vault.write("conflicts/Keep.md", String(decoding: definition, as: UTF8.self))
        #expect(try vault.index.links(to: path).contains { $0.file == storePath })
        // Every other file of the vault (each day file, the conflict copy, settings) keeps its bytes.
        var expected = try vault.allFileBytes()
        expected.removeValue(forKey: path)
        #expect(expected.keys.contains(storePath) && expected.keys.contains("conflicts/Keep.md"))
        try await vault.store.deletingEntity(path: path)
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(path).path))
        #expect(try vault.index.files().allSatisfy { $0.path != path })
        #expect(try vault.index.entities(named: "Kurgusal Varlık").isEmpty)
        #expect(try vault.allFileBytes() == expected)
        #expect(try vault.index.snapshot().links.contains { $0.target == "Kurgusal Varlık" && $0.resolvedFile == nil })
        try vault.check()
        #expect(try await vault.store.creatingEntity(kind: kind, name: "Kurgusal Varlık") == path)
        try vault.check()
    }

    @Test func goalDeletionPreservesLogsAndReleasesKey() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let path = "goals/Spor.md"
        let days = try Dictionary(
            uniqueKeysWithValues: vault.index.files().filter { $0.path.hasPrefix("journal/") }.map {
                ($0.path, try vault.bytes($0.path))
            })
        let logs = try vault.index.goalLogs()
        try await vault.store.deletingGoal(path: path)
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(path).path))
        #expect(try vault.index.goalDefinitions().allSatisfy { $0.id != path })
        #expect(try vault.index.goalLogs() == logs)
        for (path, bytes) in days { #expect(try vault.bytes(path) == bytes) }
        try vault.check()
        let recreated = try await vault.store.creatingGoal(name: "Spor", period: .week, kind: .boolean, target: 3)
        #expect(try vault.index.goalDefinitions().first { $0.id == recreated }?.key == "spor")
        try vault.check()
    }

    @Test func rejectsWrongTypeFolderHiddenAndSymlinkWithoutChangingBytes() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        for path in [storePath, "notes/Note.md", "people/Wrong.md", "goals/Wrong.md", "conflicts/Copy.md"] {
            if path != storePath { try vault.write(path, "---\ntype: person\nname: Keep\n---\nKeep\n") }
            let before = try vault.bytes(path)
            await #expect(throws: (any Error).self) { try await vault.store.deletingGoal(path: path) }
            if path != "people/Wrong.md" {
                await #expect(throws: (any Error).self) { try await vault.store.deletingEntity(path: path) }
            }
            #expect(try vault.bytes(path) == before)
        }
        let target = vault.root.appendingPathComponent("people/Wrong.md")
        let link = vault.root.appendingPathComponent("people/Link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await #expect(throws: VaultStoreError.invalidPath) {
            try await vault.store.deletingEntity(path: "people/Link.md")
        }
        #expect(FileManager.default.fileExists(atPath: target.path))
        await #expect(throws: (any Error).self) { try await vault.store.deletingEntity(path: "goals/Spor.md") }
    }

    /// Hidden names, `..` components, the app folder and a folder named like a definition are
    /// refused by the path itself, before the file's type is read; nothing on disk changes.
    @Test func rejectsHiddenTraversalAppAndFolderPathsWithoutChangingBytes() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let person = "---\ntype: person\nname: Gizli\n---\n"
        let goal = "---\ntype: goal\nname: Gizli\nkey: gizli\nperiod: day\nkind: boolean\n---\n"
        try vault.write("people/.Gizli.md", person)
        try vault.write("goals/.Gizli.md", goal)
        try vault.write(".app/Gizli.md", person)
        try vault.write("people/Klasor.md/Icerik.md", person)
        try vault.write("goals/Klasor.md/Icerik.md", goal)
        let before = try vault.allFileBytes()
        let indexed = try vault.index.files().map(\.path)
        let paths = [
            "people/.Gizli.md", "goals/.Gizli.md", ".app/Gizli.md", "../Gizli.md",
            "people/../people/Deniz Arıkan.md", "goals/../goals/Spor.md", "people/Klasor.md", "goals/Klasor.md",
        ]
        for path in paths {
            await #expect(throws: VaultStoreError.invalidPath, "\(path)") {
                try await vault.store.deletingEntity(path: path)
            }
            await #expect(throws: VaultStoreError.invalidPath, "\(path)") {
                try await vault.store.deletingGoal(path: path)
            }
        }
        #expect(try vault.allFileBytes() == before)
        #expect(try vault.index.files().map(\.path) == indexed)
    }

    @Test(arguments: [false, true])
    func pendingDownloadIsNeverRemoved(_ goal: Bool) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let folder = goal ? "goals" : "people"
        let path = folder + "/Pending.md"
        let placeholder = folder + "/.Pending.md.icloud"
        try vault.write(placeholder, "placeholder")
        await #expect(throws: VaultStoreError.awaitingDownload(path: path)) {
            if goal {
                try await vault.store.deletingGoal(path: path)
            } else {
                try await vault.store.deletingEntity(path: path)
            }
        }
        #expect(try vault.bytes(placeholder) == Data("placeholder".utf8))
    }

    @Test func coordinationDenialAndRemovalFailureKeepFileAndIndex() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let path = "people/Deniz Arıkan.md"
        let before = try vault.bytes(path)
        let boundary = DeleteBoundary()
        let denied = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: boundary)
        await #expect(throws: DeleteBoundary.Failure.denied) { try await denied.deletingEntity(path: path) }
        #expect(boundary.operation == .delete(vault.root.appendingPathComponent(path)))
        let failing = VaultStore(
            vaultRoot: vault.root, index: vault.index,
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            removeFile: { _ in throw DeleteBoundary.Failure.denied })
        await #expect(throws: DeleteBoundary.Failure.denied) { try await failing.deletingEntity(path: path) }
        #expect(try vault.bytes(path) == before)
        #expect(try vault.index.entities(named: "Deniz Arıkan").count == 1)
        try vault.check()
    }
}

extension StoreVault {
    /// Every regular file under the vault root, hidden ones included, by relative path.
    fileprivate func allFileBytes() throws -> [String: Data] {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        var files: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            files[String(path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return files
    }
}

private final class DeleteBoundary: FileCoordination, @unchecked Sendable {
    enum Failure: Error { case denied }
    private let lock = NSLock()
    private var recorded: FileCoordinationOperation?
    var operation: FileCoordinationOperation? { lock.withLock { recorded } }
    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        lock.withLock { recorded = operation }
        throw Failure.denied
    }
}
