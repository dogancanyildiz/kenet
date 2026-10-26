import Foundation
import Testing
import VaultFormat
import VaultStore

struct RelationsWriteTests {
    struct Description: Decodable { let relation: Operation }

    struct Operation: Decodable {
        let target: String
        let label: String?
        let remove: Bool
        let error: String?
        let source: String?
        let extraFiles: [String: String]?
    }

    static func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: Fixtures.root().appendingPathComponent("write/relations").path
        ).sorted()
    }

    @Test(arguments: try names())
    func fixtures(_ name: String) async throws {
        let folder = try Fixtures.root().appendingPathComponent("write/relations/" + name)
        let input = try Data(contentsOf: folder.appendingPathComponent("input.md"))
        let expected = try Data(contentsOf: folder.appendingPathComponent("expected.md"))
        let operation = try JSONDecoder().decode(
            Description.self,
            from: Data(contentsOf: folder.appendingPathComponent("operation.json"))
        ).relation
        let vault = try StoreVault()
        defer { vault.remove() }
        let path = operation.source ?? "people/Deniz Arıkan.md"
        for name in ["Selin Korkmaz", "Baran Tunç"] {
            try vault.write("people/" + name + ".md", "---\ntype: person\nname: " + name + "\n---\n")
        }
        try vault.write("places/Liman Ofis.md", "---\ntype: place\nname: Liman Ofis\n---\n")
        try vault.write(
            ".app/types.json",
            """
            {"formatVersion":1,"types":[{"id":"book","folder":"books",
            "name":{"tr":"Kitap","en":"Book"},"plural":{"tr":"Kitaplar","en":"Books"},
            "icon":"book","fields":[{"key":"yazar","kind":"link"},{"key":"başlık","kind":"text"}]}]}
            """)
        for (file, text) in operation.extraFiles ?? [:] { try vault.write(file, text) }
        try vault.write(path, String(decoding: input, as: UTF8.self))
        let beforeFiles = try Dictionary(
            uniqueKeysWithValues:
                FileManager.default.subpathsOfDirectory(atPath: vault.root.path)
                .filter { $0.hasSuffix(".md") && $0 != path }
                .map { ($0, try vault.bytes($0)) })
        #expect(Data(RawDocument(bytes: input).serialized()) == input)
        #expect(Data(RawDocument(bytes: expected).serialized()) == expected)
        do {
            if operation.remove {
                try await vault.store.removeRelation(from: path, to: operation.target, label: operation.label)
            } else {
                try await vault.store.addRelation(from: path, to: operation.target, label: operation.label)
            }
            #expect(operation.error == nil)
        } catch {
            switch operation.error {
            case "keyInUse": #expect(error as? RelationError == .keyInUse)
            case "invalidLabel": #expect(error as? RelationError == .invalidLabel)
            case "invalidTarget": #expect(error as? RelationError == .invalidTarget)
            case "invalidSource": #expect(error as? RelationError == .invalidSource)
            case "unsafeRemoval": #expect(error as? RelationError == .unsafeRemoval)
            case "reservedLabel": #expect(error as? RelationError == .reservedLabel)
            case "unreadableFrontmatter": #expect(error as? EditError == .unreadableFrontmatter)
            default: throw error
            }
        }
        #expect(try vault.bytes(path) == expected)
        for (file, bytes) in beforeFiles { #expect(try vault.bytes(file) == bytes) }
        if operation.error == nil { try vault.check() }
    }

    @Test(arguments: ["type", "name", "qualifier", "aliases", "related"])
    func everyReservedLabelIsRejected(_ label: String) async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let path = "people/Deniz Arıkan.md"
        let before = try vault.bytes(path)
        await #expect(throws: RelationError.reservedLabel) {
            try await vault.store.addRelation(from: path, to: "Selin Korkmaz", label: label)
        }
        await #expect(throws: RelationError.reservedLabel) {
            try await vault.store.removeRelation(from: path, to: "Selin Korkmaz", label: label)
        }
        #expect(try vault.bytes(path) == before)
    }

    @Test func readOnlyVaultRejectsAddAndRemove() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let path = "people/Deniz Arıkan.md"
        try await vault.store.addRelation(from: path, to: "Selin Korkmaz", label: "eşi")
        try vault.write(".app/vault.json", "{ \"formatVersion\": 2 }\n")
        let before = try vault.bytes(path)
        await #expect(throws: VaultStoreError.readOnlyVault) {
            try await vault.store.addRelation(from: path, to: "Selin Korkmaz")
        }
        await #expect(throws: VaultStoreError.readOnlyVault) {
            try await vault.store.removeRelation(from: path, to: "Selin Korkmaz", label: "eşi")
        }
        #expect(try vault.bytes(path) == before)
    }

    @Test func concurrentAddsToOneSourceLoseNoRelations() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let path = "people/Deniz Arıkan.md"
        let names = (0..<12).map { "Kişi " + String($0) }
        try vault.write(path, "---\ntype: person\nname: Deniz Arıkan\n---\n")
        for name in names {
            try vault.write("people/" + name + ".md", "---\ntype: person\nname: " + name + "\n---\n")
        }
        try vault.index.rebuild(vaultRoot: vault.root)
        // Two stores share the per-root write queue; neither may overwrite the other's edit.
        let second = VaultStore(vaultRoot: vault.root, index: vault.index)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (number, name) in names.enumerated() {
                group.addTask {
                    let store = number.isMultiple(of: 2) ? vault.store : second
                    try await store.addRelation(from: path, to: name)
                }
            }
            try await group.waitForAll()
        }
        guard case .parsed(let frontmatter) = RawDocument(bytes: try vault.bytes(path)).frontmatter else {
            Issue.record("frontmatter is not readable")
            return
        }
        let items = frontmatter.field(named: "related")?.value.listItems?.map(\.text) ?? []
        #expect(items.count == names.count)
        #expect(Set(items) == Set(names.map { "[[" + $0 + "]]" }))
        let outgoing = try vault.index.relations(of: path).outgoing
        #expect(Set(outgoing.map(\.target)) == Set(names.map { "people/" + $0 + ".md" }))
        try vault.check()
    }

    @Test func renameUpdatesBothRelationFields() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let path = "people/Deniz Arıkan.md"
        try await vault.store.addRelation(from: path, to: "Selin Korkmaz")
        try await vault.store.addRelation(from: path, to: "Selin Korkmaz", label: "eşi")
        let before = try vault.bytes(path)
        let renamed = try await vault.store.renamingEntity(at: "people/Selin Korkmaz.md", to: "Selin Tunç")
        #expect(renamed.failures.isEmpty)
        #expect(
            try vault.bytes(path)
                == Data(
                    String(decoding: before, as: UTF8.self)
                        .replacingOccurrences(of: "[[Selin Korkmaz]]", with: "[[Selin Tunç]]").utf8))
        #expect(try vault.index.relations(of: path).outgoing.count == 2)
        #expect(try vault.index.relations(of: renamed.path).incoming.count == 2)
        try vault.check()
    }
}
