import Foundation
import Testing
import VaultFormat

@testable import VaultStore

struct DiaryTests {
    @Test func diaryNewReplacementAndEmptyHaveExactBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.changingDiary(on: storeDate, to: "Kitap\nSu")
        #expect(try vault.bytes() == Data("---\ntype: diary\ndate: 2026-09-27\n---\n\n## Diary\nKitap\nSu\n".utf8))
        try vault.check()
        try await vault.store.changingDiary(on: storeDate, to: "Deniz")
        #expect(try vault.bytes() == Data("---\ntype: diary\ndate: 2026-09-27\n---\n\n## Diary\nDeniz\n".utf8))
        try vault.check()
        try await vault.store.changingDiary(on: storeDate, to: "")
        #expect(try vault.bytes() == Data("---\ntype: diary\ndate: 2026-09-27\n---\n\n## Diary\n".utf8))
        try vault.check()
    }

    @Test(arguments: ["# Kitap", "## Kitap", "```\nSu"])
    func structuralContentIsRejected(text: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Diary\nKitap\n")
        let before = try vault.bytes()
        await #expect(throws: EditError.sectionNotWritable) {
            try await vault.store.changingDiary(on: storeDate, to: text)
        }
        #expect(try vault.bytes() == before)
        #expect(try vault.index.files().isEmpty)
    }

    @Test func outsideBytesIncludingBOMAndMixedEndingsAreUnchanged() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let prefix = "\u{FEFF}---\r\ntype: note\ncustom: 20.0290\r---\r\n\r\n## Events\n- Su ^old\r\n## Diary\r\n"
        let suffix = "## Other\rDeniz"
        try vault.write(storePath, prefix + "Kitap\n\n" + suffix)
        try await vault.store.changingDiary(on: storeDate, to: "Selin")
        #expect(try vault.bytes() == Data((prefix + "Selin\r\n\n" + suffix).utf8))
        try vault.check()
    }
    @Test(arguments: ["Kitap\n\n", "Kitap\n \n\t", " \n\t"])
    func repeatedDiarySaveDoesNotGrowOrRewrite(text: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Diary\nSu\n\n## Notes\nDeniz\n")
        let first = try await vault.store.changingDiary(on: storeDate, to: text)
        let url = vault.root.appendingPathComponent(storePath)
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        let second = try await vault.store.changingDiary(on: storeDate, to: text)
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(first.serialized() == second.serialized())
        #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
        #expect(before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber)
        let content = text.hasPrefix("Kitap") ? "Kitap\n" : ""
        #expect(try vault.bytes() == Data(("## Diary\n" + content + "\n## Notes\nDeniz\n").utf8))
        try vault.check()
    }

    /// Another process changes the section after the editor read it, at the moment the write's
    /// coordinated `.modify` access begins: the comparison with `expectedBody` must run inside that
    /// access, so the change stays. A comparison made before the access (a separate read) would see
    /// the old section, pass, and the write would erase the change.
    @Test func diaryChangedBeforeTheWriteIsStaleAndKept() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Diary\nKitap\n")
        try vault.index.rebuild(vaultRoot: vault.root)
        let external = Data("## Diary\nKitap\nSu\n".utf8)
        let coordination = WriteOnModify(fileName: "2026-09-27.md", bytes: external)
        let store = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: coordination)
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.changingDiary(on: storeDate, to: "Deniz", expectedBody: "Kitap\n")
        }
        #expect(coordination.fired)
        #expect(try vault.bytes() == external)
    }

    @Test func diaryMatchingExpectedBodyIsWritten() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.changingDiary(on: storeDate, to: "Kitap", expectedBody: "")
        #expect(try vault.bytes() == Data("---\ntype: diary\ndate: 2026-09-27\n---\n\n## Diary\nKitap\n".utf8))
        try await vault.store.changingDiary(on: storeDate, to: "Deniz", expectedBody: "Kitap\n")
        #expect(try vault.bytes() == Data("---\ntype: diary\ndate: 2026-09-27\n---\n\n## Diary\nDeniz\n".utf8))
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.changingDiary(on: storeDate, to: "Su", expectedBody: "Kitap\n")
        }
        try vault.check()
    }
}

/// Coordination whose first `.modify` access to `fileName` writes `bytes` into the file before
/// the accessor runs: the test's stand-in for another process writing at that exact moment.
final class WriteOnModify: FileCoordination, @unchecked Sendable {
    private let lock = NSLock()
    private let fileName: String
    private let bytes: Data
    private var done = false

    init(fileName: String, bytes: Data) {
        self.fileName = fileName
        self.bytes = bytes
    }

    var fired: Bool { lock.withLock { done } }

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        if case .modify(let url) = operation, url.lastPathComponent == fileName {
            let fire = lock.withLock {
                defer { done = true }
                return !done
            }
            if fire { try bytes.write(to: url) }
        }
        return try accessor(FileCoordinationAccess())
    }
}
