import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import VaultIndex

/// `Fixtures/vaults/turkce-buyuk-harf`: the Turkish capitals `İ` → `i` and `I` → `ı` in the name
/// key, link resolution, recognition and the name collision checks (`docs/vault-format.md`).
@Suite struct TurkishCapitalTests {
    struct Expected: Decodable {
        struct Key: Decodable {
            let text: String
            let key: String
        }
        struct Entity: Decodable {
            let file: String
            let comparisonKey: String
        }
        struct Link: Decodable {
            let line: Int
            let target: String
            let targetKey: String
            let resolvedFile: String?
        }
        struct Named: Decodable {
            let name: String
            let files: [String]
        }
        struct Mention: Decodable, Equatable {
            let line: Int
            let byteRange: [Int]
            let spelling: String
            let isCaseMismatch: Bool
        }
        struct Query: Decodable {
            let entity: String
            let mentions: [Mention]
        }
        struct Creation: Decodable {
            let kind: String
            let name: String
            let result: String
        }
        struct Rename: Decodable {
            let from: String
            let to: String
            let result: String
        }
        struct Placeholder: Decodable {
            let placeholder: String
            let kind: String
            let name: String
            let awaiting: String
        }
        let keys: [Key]
        let files: [String]
        let entities: [Entity]
        let aliases: [Entity]
        let links: [Link]
        let named: [Named]
        let mentions: [Query]
        let creations: [Creation]
        let renames: [Rename]
        let placeholders: [Placeholder]
    }

    private static let fixture = "vaults/turkce-buyuk-harf"

    private static func expected() throws -> Expected {
        try JSONDecoder().decode(
            Expected.self,
            from: Data(contentsOf: Fixtures.root().appendingPathComponent(fixture + "/expected.json")))
    }

    /// A scratch copy of the fixture vault with its own index database.
    private struct Scratch {
        let directory: URL
        let root: URL
        let index: VaultIndex
        let store: VaultStore

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            root = directory.appendingPathComponent("vault")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: Fixtures.root().appendingPathComponent(TurkishCapitalTests.fixture), to: root)
            try FileManager.default.removeItem(at: root.appendingPathComponent("expected.json"))
            index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
            try index.rebuild(vaultRoot: root)
            store = VaultStore(vaultRoot: root, index: index)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }

        func diskBytes() throws -> [String: Data] {
            var result: [String: Data] = [:]
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            while let url = enumerator?.nextObject() as? URL {
                guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true else { continue }
                result[url.path] = try Data(contentsOf: url)
            }
            return result
        }
    }

    private func bytes(_ text: String?) -> [UInt8]? { text.map { Array($0.utf8) } }

    private func kind(_ text: String) -> VaultEntityKind { text == "place" ? .place : .person }

    @Test func keysFoldTurkishCapitalsBeforeLowercasing() throws {
        for item in try Self.expected().keys {
            // The stored key is NFC bytes; the recognizer's fold is canonically the same text.
            #expect(bytes(nameComparisonKey(item.text)) == bytes(item.key), "\(item.text)")
            #expect(nameComparisonFold(item.text) == item.key, "\(item.text)")
        }
    }

    @Test func indexStoresKeysAndResolvesLinksByThem() throws {
        let expected = try Self.expected()
        let scratch = try Scratch()
        defer { scratch.remove() }
        let snapshot = try scratch.index.snapshot()
        #expect(snapshot.files.map { bytes($0.path) } == expected.files.map { bytes($0) })
        #expect(
            snapshot.entities.map { [bytes($0.file), bytes($0.comparisonKey)] }
                == expected.entities.map { [bytes($0.file), bytes($0.comparisonKey)] })
        #expect(
            snapshot.aliases.map { [bytes($0.file), bytes($0.comparisonKey)] }
                == expected.aliases.map { [bytes($0.file), bytes($0.comparisonKey)] })
        #expect(snapshot.links.map(\.line) == expected.links.map(\.line))
        #expect(
            snapshot.links.map { [bytes($0.target), bytes($0.targetKey), bytes($0.resolvedFile)] }
                == expected.links.map { [bytes($0.target), bytes($0.targetKey), bytes($0.resolvedFile)] })
        for named in expected.named {
            #expect(try scratch.index.entities(named: named.name).map(\.file) == named.files, "\(named.name)")
        }
    }

    @Test func recognitionFindsTurkishCapitalSpellings() throws {
        let expected = try Self.expected()
        let scratch = try Scratch()
        defer { scratch.remove() }
        let entities = try scratch.index.unlinkedMentionEntities()
        #expect(Set(entities.map(\.file)) == Set(expected.mentions.map(\.entity)))
        for query in expected.mentions {
            let entity = try #require(entities.first { $0.file == query.entity })
            let actual = try scratch.index.unlinkedMentions(of: entity, vaultRoot: scratch.root)
            #expect(
                actual.map {
                    Expected.Mention(
                        line: $0.position.line,
                        byteRange: [$0.position.byteRange.lowerBound, $0.position.byteRange.upperBound],
                        spelling: $0.spelling, isCaseMismatch: $0.isCaseMismatch)
                } == query.mentions, "\(query.entity)")
            // The search stage only narrows the days read; reading every day finds the same mentions.
            #expect(
                try scratch.index.unlinkedMentions(
                    of: entity, entities: entities, days: scratch.index.unlinkedMentionDays(naming: nil),
                    vaultRoot: scratch.root) == actual)
        }
    }

    @Test func creationRejectsNamesThatCollide() async throws {
        for creation in try Self.expected().creations {
            let scratch = try Scratch()
            defer { scratch.remove() }
            let before = try scratch.diskBytes()
            do {
                let path = try await scratch.store.creatingEntity(kind: kind(creation.kind), name: creation.name)
                #expect(bytes(path) == bytes(creation.result), "\(creation.name)")
            } catch VaultStoreError.nameTaken {
                #expect(creation.result == "nameTaken", "\(creation.name)")
                #expect(try scratch.diskBytes() == before)
            }
        }
    }

    @Test func renameRejectsNamesThatCollide() async throws {
        for rename in try Self.expected().renames {
            let scratch = try Scratch()
            defer { scratch.remove() }
            let before = try scratch.diskBytes()
            do {
                let result = try await scratch.store.renamingEntity(at: rename.from, to: rename.to)
                #expect(bytes(result.path) == bytes(rename.result), "\(rename.to)")
            } catch VaultStoreError.nameTaken {
                #expect(rename.result == "nameTaken", "\(rename.to)")
                #expect(try scratch.diskBytes() == before)
            }
        }
    }

    @Test func placeholderSiblingCollidesByEitherReading() async throws {
        for item in try Self.expected().placeholders {
            let scratch = try Scratch()
            defer { scratch.remove() }
            try Data("bplist00".utf8).write(to: scratch.root.appendingPathComponent(item.placeholder))
            let before = try scratch.diskBytes()
            do {
                _ = try await scratch.store.creatingEntity(kind: kind(item.kind), name: item.name)
                Issue.record("expected awaitingDownload for \(item.name)")
            } catch VaultStoreError.awaitingDownload(let path) {
                // Darwin may store the placeholder's name decomposed; the error carries the disk spelling.
                #expect(path == item.awaiting)
            }
            #expect(try scratch.diskBytes() == before)
        }
    }

    /// An index written under the previous schema holds keys the old rule made; opening it erases it.
    @Test func previousSchemaIndexIsErasedAndRebuiltWithNewKeys() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let url = scratch.directory.appendingPathComponent("previous.sqlite")
        do {
            let previous = try VaultIndex(databaseURL: url)
            try previous.rebuild(vaultRoot: scratch.root)
            try previous.database.write { db in
                try db.execute(sql: "UPDATE entities SET comparisonKey = 'işık' WHERE file = 'people/Işık.md'")
                try db.execute(sql: "PRAGMA user_version = 8")
            }
        }
        let reopened = try VaultIndex(databaseURL: url)
        #expect(try reopened.files().isEmpty)
        #expect(try reopened.database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 9)
        try reopened.refresh(vaultRoot: scratch.root)
        #expect(try reopened.entities(named: "IŞIK").map(\.file) == ["people/Işık.md"])
        #expect(try reopened.entities(named: "işık").isEmpty)
    }
}
