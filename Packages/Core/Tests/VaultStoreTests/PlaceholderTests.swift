import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import VaultIndex

struct PlaceholderTests {
    private struct NameCase: Decodable {
        let name: String
        let original: String?
    }

    private struct Expected: Decodable {
        let pending: [String]
        let files: [String]
    }

    private func fixture() throws -> URL {
        try Fixtures.root().appendingPathComponent("vaults/placeholder")
    }

    @Test func placeholderNamesPreserveBytes() throws {
        let cases = try JSONDecoder().decode(
            [NameCase].self, from: Data(contentsOf: fixture().appendingPathComponent("names.json")))
        for value in cases {
            let original = PlaceholderName.originalName(ofPlaceholder: value.name)
            #expect(original.map { Array($0.utf8) } == value.original.map { Array($0.utf8) })
            #expect(PlaceholderName.isPlaceholder(fileName: value.name) == (value.original != nil))
            if let original = value.original {
                #expect(PlaceholderName.placeholderName(for: original).utf8.elementsEqual(value.name.utf8))
            }
        }
    }

    @Test func placeholderScanResults() throws {
        let root = try fixture()
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
        let index = try VaultIndex()
        for result in [try index.rebuild(vaultRoot: root), try index.refresh(vaultRoot: root)] {
            #expect(result.pendingDownloads == expected.pending)
            #expect(try index.files().map(\.path) == expected.files)
        }
        for path in expected.pending {
            let parent = (path as NSString).deletingLastPathComponent
            let name = PlaceholderName.placeholderName(for: (path as NSString).lastPathComponent)
            let placeholder = parent.isEmpty ? name : parent + "/" + name
            let result = try index.update(paths: [placeholder], vaultRoot: root)
            #expect(result.pendingDownloads == [path])
            #expect(try index.files().map(\.path) == expected.files)
        }
        #expect(try index.update(paths: ["journal"], vaultRoot: root).pendingDownloads == ["journal/2026-09-30.md"])
        #expect(try index.update(paths: ["journal/.2026-10-01.md.icloud"], vaultRoot: root).pendingDownloads.isEmpty)
    }

    @Test func evictedDayReportsPendingAndDownloadedDayReturns() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture(), to: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let path = "journal/2026-10-01.md"
        let url = root.appendingPathComponent(path)
        let original = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        let result = try index.update(paths: ["journal/.2026-10-01.md.icloud"], vaultRoot: root)
        #expect(result.deletedPaths == [path])
        #expect(result.pendingDownloads == [path])
        #expect(try index.files().contains { $0.path == path } == false)
        try original.write(to: url)
        let downloaded = try index.update(paths: [path], vaultRoot: root)
        #expect(downloaded.addedPaths == [path])
        #expect(downloaded.pendingDownloads.isEmpty)
        try equivalent(index, root)
    }

    enum Creation: String, CaseIterable, Sendable {
        case day, entity, goal, rename, types

        var path: String {
            switch self {
            case .day: "journal/2026-09-30.md"
            case .entity, .rename: "people/Selin Korkmaz.md"
            case .goal: "goals/Su.md"
            case .types: ".app/types.json"
            }
        }

        func perform(_ store: VaultStore) async throws {
            switch self {
            case .day: _ = try await store.addingEvent(on: CalendarDate("2026-09-30")!, text: "Kitap")
            case .entity: _ = try await store.creatingEntity(kind: .person, name: "Selin Korkmaz")
            case .goal: _ = try await store.creatingGoal(name: "Su", period: .day, kind: .number, target: 8)
            case .rename: _ = try await store.renamingEntity(at: "people/Deniz Arıkan.md", to: "Selin Korkmaz")
            case .types:
                try await store.savingEntityType(
                    EntityTypeDefinition(
                        id: "album", folder: "albums", name: .init(tr: "Albüm", en: "Album"),
                        plural: .init(tr: "Albümler", en: "Albums"), icon: "opticaldisc"))
            }
        }
    }

    @Test(arguments: Creation.allCases, [false, true])
    func placeholderCreationRejected(creation: Creation, arrivesInsideBoundary: Bool) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let root = scratch.appendingPathComponent("source")
        try FileManager.default.copyItem(at: fixture(), to: root)
        let url = root.appendingPathComponent(creation.path)
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(
            PlaceholderName.placeholderName(for: url.lastPathComponent))
        let bytes = try Data(contentsOf: placeholder)
        if arrivesInsideBoundary { try FileManager.default.removeItem(at: placeholder) }
        let index = try VaultIndex(databaseURL: scratch.appendingPathComponent("index.sqlite"))
        try index.rebuild(vaultRoot: root)
        let store = VaultStore(
            vaultRoot: root, index: index,
            fileCoordination: ArrivalCoordination(placeholder: arrivesInsideBoundary ? placeholder : nil, bytes: bytes))
        let snapshot = try index.snapshot()
        let before = try diskBytes(scratch)
        await #expect(throws: VaultStoreError.awaitingDownload(path: creation.path)) {
            try await creation.perform(store)
        }
        var expected = before
        if arrivesInsideBoundary {
            expected[
                "source/" + (creation.path as NSString).deletingLastPathComponent + "/" + placeholder.lastPathComponent] =
                bytes
        }
        #expect(try diskBytes(scratch) == expected)
        #expect(try index.snapshot() == snapshot)
    }

    /// Siblings match by the vault's comparison key, not by the volume: on a case-sensitive volume
    /// (iOS devices, Linux) only the key catches `selin korkmaz.md` beside `.Selin Korkmaz.md.icloud`.
    /// The error names the placeholder's on-disk spelling, which the host downloads.
    @Test func placeholderSiblingMatchesByComparisonKey() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let root = scratch.appendingPathComponent("source")
        try FileManager.default.copyItem(at: fixture(), to: root)
        let decomposed = "Go\u{308}kc\u{327}e.md"
        let places = root.appendingPathComponent("places")
        try FileManager.default.createDirectory(at: places, withIntermediateDirectories: true)
        try Data("bplist00".utf8).write(
            to: places.appendingPathComponent(PlaceholderName.placeholderName(for: decomposed)))
        let index = try VaultIndex(databaseURL: scratch.appendingPathComponent("index.sqlite"))
        try index.rebuild(vaultRoot: root)
        let store = VaultStore(vaultRoot: root, index: index)
        let snapshot = try index.snapshot()
        let before = try diskBytes(scratch)
        let cases: [(String, @Sendable () async throws -> Void)] = [
            ("people/Selin Korkmaz.md", { _ = try await store.creatingEntity(kind: .person, name: "selin korkmaz") }),
            (
                "people/Selin Korkmaz.md",
                { _ = try await store.renamingEntity(at: "people/Deniz Arıkan.md", to: "SELIN KORKMAZ") }
            ),
            ("places/" + decomposed, { _ = try await store.creatingEntity(kind: .place, name: "Gökçe") }),
        ]
        for (expected, operation) in cases {
            // String equality is canonical; the spelling the host downloads must match byte for byte.
            do {
                try await operation()
                Issue.record("expected awaitingDownload for \(expected)")
            } catch VaultStoreError.awaitingDownload(let path) {
                #expect(Array(path.utf8) == Array(expected.utf8))
            }
        }
        #expect(try diskBytes(scratch) == before)
        #expect(try index.snapshot() == snapshot)
    }

    @Test func downloadedOriginalRemainsEditable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture(), to: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let store = VaultStore(vaultRoot: root, index: index, randomValue: { 0 })
        let placeholder = root.appendingPathComponent("journal/.2026-10-01.md.icloud")
        let before = try Data(contentsOf: placeholder)
        let result = try await store.addingEvent(on: CalendarDate("2026-10-01")!, text: "Su")
        #expect(result.bodyLines.events.map(\.block.text) == ["Kitap", "Su"])
        #expect(try Data(contentsOf: placeholder) == before)
        #expect(try index.refresh(vaultRoot: root).pendingDownloads.contains("journal/2026-10-01.md") == false)
        try equivalent(index, root)
    }

    private func diskBytes(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path) {
            let url = root.appendingPathComponent(path)
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue {
                result[path] = try Data(contentsOf: url)
            }
        }
        return result
    }
}

private struct ArrivalCoordination: FileCoordination {
    let placeholder: URL?
    let bytes: Data

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        if let placeholder { try bytes.write(to: placeholder) }
        return try accessor(FileCoordinationAccess())
    }
}
