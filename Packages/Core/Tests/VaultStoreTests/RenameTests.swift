import EntityRecognition
import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

struct RenameTests {
    struct Case: Decodable {
        let path: String
        let name: String
        let qualifier: String?
        let newPath: String
        let failures: Int
        let updatedFiles: [String]
        let failureDetails: [FailureDetail]
        struct FailureDetail: Decodable {
            let path: String
            let kind: String
            let detail: String
        }
        let afterIndex: AfterIndex?
        struct AfterIndex: Decodable {
            let path: String
            let bytes: [UInt8]
        }
    }

    @Test(arguments: [
        "body-mixed-line-endings-bom-no-final-newline", "frontmatter", "qualifier", "same-filename",
        "read-only-invalid-utf8", "list-2-grows", "list-2-shrinks", "list-3-grows", "list-3-shrinks",
        "unrelated-fields", "empty-list-item",
    ])
    func portableFixtures(_ name: String) async throws {
        let folder = try Fixtures.root().appendingPathComponent("rename/" + name)
        let spec = try JSONDecoder().decode(
            Case.self, from: Data(contentsOf: folder.appendingPathComponent("case.json")))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: folder.appendingPathComponent("input"), to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        if let edit = spec.afterIndex { try Data(edit.bytes).write(to: root.appendingPathComponent(edit.path)) }
        let result = try await VaultStore(vaultRoot: root, index: index).renamingEntity(
            at: spec.path, to: spec.name, qualifier: spec.qualifier)
        #expect(result.path == spec.newPath)
        #expect(result.failures.count == spec.failures)
        #expect(result.updatedFiles == spec.updatedFiles)
        for (failure, expected) in zip(result.failures, spec.failureDetails) {
            #expect(failure.path == expected.path)
            switch failure.reason {
            case .rawField(let key): #expect(expected.kind == "rawField" && key == expected.detail)
            case .file(let reason): #expect(expected.kind == "file" && reason.contains(expected.detail))
            case .frontmatterList(let key, _):
                #expect(expected.kind == "frontmatterList" && key == expected.detail)
            default: Issue.record("Unexpected failure reason: \(failure.reason)")
            }
        }
        #expect(spec.failureDetails.count == result.failures.count)
        let expected = folder.appendingPathComponent("expected")
        let expectedPaths = try FileManager.default.subpathsOfDirectory(atPath: expected.path).filter {
            $0.hasSuffix(".md")
        }.sorted()
        let actualPaths = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".md") }
            .sorted()
        #expect(actualPaths == expectedPaths)
        for path in expectedPaths {
            #expect(
                try Data(contentsOf: root.appendingPathComponent(path))
                    == Data(contentsOf: expected.appendingPathComponent(path)), "\(name): \(path)")
        }
        try equivalent(index, root)
    }

    @Test func sampleSevenLinksAndAllUnrelatedBytesArePreserved() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let path = "people/Deniz Arıkan.md"
        let links = try vault.index.links(to: path)
        #expect(links.count == 7)
        let sourcePaths = Set(links.map(\.file))
        let before = try Dictionary(
            uniqueKeysWithValues: vault.index.files().map { ($0.path, try vault.bytes($0.path)) })
        let result = try await vault.store.renamingEntity(at: path, to: "Deniz Arıkan Yılmaz")
        #expect(result.failures.isEmpty)
        #expect(Set(result.updatedFiles) == sourcePaths.union([result.path]))
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(path).path))
        for (file, bytes) in before {
            let expected: Data
            let destination = file == path ? result.path : file
            if file == path {
                expected = Data(
                    String(decoding: bytes, as: UTF8.self).replacingOccurrences(
                        of: "name: Deniz Arıkan", with: "name: Deniz Arıkan Yılmaz"
                    ).utf8)
            } else if sourcePaths.contains(file) {
                expected = Data(
                    String(decoding: bytes, as: UTF8.self).replacingOccurrences(
                        of: "[[Deniz Arıkan", with: "[[Deniz Arıkan Yılmaz"
                    ).utf8)
            } else {
                expected = bytes
            }
            #expect(try vault.bytes(destination) == expected)
        }
        let renamed = try vault.index.links(to: result.path)
        #expect(renamed.count == 7)
        #expect(renamed.map(\.displayText) == links.map(\.displayText))
        #expect(renamed.map(\.anchor) == links.map(\.anchor))
        #expect(try vault.index.knownEntities().first { $0.file == result.path }?.name == "Deniz Arıkan Yılmaz")
        let mentions = EntityRecognizer.recognize("Deniz Arıkan Yılmaz", entities: try vault.index.knownEntities())
        #expect(mentions.first?.isCertain == true)
        #expect(mentions.first?.candidates.first?.file == result.path)
        try vault.check()
    }

    @Test func samplePlaceFrontmatterIsQuoted() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let before = try vault.bytes("goals/Spor.md")
        let result = try await vault.store.renamingEntity(
            at: "places/Tepe Spor Salonu.md", to: "Tepe Spor Salonu", qualifier: "iş")
        #expect(result.failures.isEmpty)
        #expect(
            try vault.bytes("goals/Spor.md")
                == Data(
                    String(decoding: before, as: UTF8.self).replacingOccurrences(
                        of: "[[Tepe Spor Salonu]]", with: "[[Tepe Spor Salonu (iş)]]"
                    ).utf8))
        try vault.check()
    }

    @Test func nameTakenChecksUnindexedDiskAndLeavesBothFilesUntouched() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let path = "people/Deniz Arıkan.md"
        let before = try vault.bytes(path)
        try vault.write("notes/deniz arıkan yılmaz.md", "Su")
        await #expect(throws: VaultStoreError.nameTaken) {
            try await vault.store.renamingEntity(at: path, to: "deniz arıkan yılmaz")
        }
        #expect(try vault.bytes(path) == before)
        #expect(try vault.bytes("notes/deniz arıkan yılmaz.md") == Data("Su".utf8))
        await #expect(throws: VaultStoreError.nameTaken) {
            try await vault.store.renamingEntity(at: path, to: "Selin Korkmaz")
        }
    }

    @Test func staleRangesAndChangedTargetAreReadFromDisk() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        try vault.write("notes/Su.md", "[[Deniz Arıkan|Deniz]] [[Selin Korkmaz]]\n")
        try vault.index.refresh(vaultRoot: vault.root)
        try vault.write("notes/Su.md", "New text\n[[Selin Korkmaz]] [[Deniz Arıkan#Başlık|Deniz]]\n")
        _ = try await vault.store.renamingEntity(at: "people/Deniz Arıkan.md", to: "Deniz Arıkan Yılmaz")
        #expect(
            try vault.bytes("notes/Su.md")
                == Data("New text\n[[Selin Korkmaz]] [[Deniz Arıkan Yılmaz#Başlık|Deniz]]\n".utf8))
        try vault.check()
    }

    @Test func duplicateBasenamesHaveIndependentPathOwnership() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write("people/Deniz Arıkan.md", "---\ntype: person\nname: Deniz Arıkan\n---\n")
        try vault.write("notes/Deniz Arıkan.md", "Su")
        try vault.write("notes/Kitap.md", "[[Deniz Arıkan]] [[people/Deniz Arıkan]] [[notes/Deniz Arıkan|Deniz]]\n")
        try vault.index.refresh(vaultRoot: vault.root)
        let result = try await vault.store.renamingEntity(at: "people/Deniz Arıkan.md", to: "Deniz Arıkan Yılmaz")
        #expect(result.failures.isEmpty)
        #expect(
            try vault.bytes("notes/Kitap.md")
                == Data("[[Deniz Arıkan]] [[people/Deniz Arıkan Yılmaz]] [[notes/Deniz Arıkan|Deniz]]\n".utf8))
        try vault.check()
    }

    @Test func newDiskDuplicateChangesOwnershipBeforeRename() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write("people/Deniz Arıkan.md", "---\ntype: person\nname: Deniz Arıkan\n---\n")
        try vault.write("notes/Su.md", "[[Deniz Arıkan|Deniz]] [[people/Deniz Arıkan]]\n")
        try vault.index.refresh(vaultRoot: vault.root)
        // The watcher has not indexed this earlier basename owner yet.
        try vault.write("notes/Deniz Arıkan.md", "Kitap")
        _ = try await vault.store.renamingEntity(at: "people/Deniz Arıkan.md", to: "Deniz Arıkan Yılmaz")
        #expect(try vault.bytes("notes/Su.md") == Data("[[Deniz Arıkan|Deniz]] [[people/Deniz Arıkan Yılmaz]]\n".utf8))
        try vault.check()
    }

    @Test func invalidNamesAndCaseOnlyRename() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        for name in [" ", ".", "[[]]", String(repeating: "D", count: 256)] {
            await #expect(throws: VaultStoreError.invalidName) {
                try await vault.store.renamingEntity(at: "people/Deniz Arıkan.md", to: name)
            }
        }
        let result = try await vault.store.renamingEntity(at: "people/Deniz Arıkan.md", to: "deniz Arıkan")
        #expect(result.path == "people/deniz Arıkan.md")
        #expect(result.failures.isEmpty)
        #expect(try vault.index.links(to: result.path).count == 7)
        try vault.check()
    }

    @Test func identicalRenameIsNoOpAndSanitizedNameOnlyChangesMetadata() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let path = "people/Deniz Arıkan.md"
        let before = try vault.bytes(path)
        let noOp = try await vault.store.renamingEntity(at: path, to: "Deniz Arıkan")
        #expect(noOp.updatedFiles.isEmpty)
        #expect(try vault.bytes(path) == before)
        let sameFile = try await vault.store.renamingEntity(at: path, to: "Deniz Arıkan?")
        #expect(sameFile.path == path)
        #expect(sameFile.updatedFiles == [path])
        #expect(try vault.index.links(to: path).count == 7)
        #expect(
            try vault.bytes(path)
                == Data(
                    String(decoding: before, as: UTF8.self).replacingOccurrences(
                        of: "name: Deniz Arıkan", with: "name: Deniz Arıkan?"
                    ).utf8))
        try vault.check()
    }
}
