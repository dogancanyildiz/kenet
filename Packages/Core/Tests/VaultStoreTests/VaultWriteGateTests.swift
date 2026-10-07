import Foundation
import Testing
import VaultFormat
import VaultIndex
@testable import VaultStore

struct VaultWriteGateTests {
    @Test func newerFormatVersionRejectsWriteWithoutRereadingUnchangedVaultJSON() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let date = CalendarDate("2026-10-04")!
        let settings = vault.root.appendingPathComponent(".app/vault.json")
        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ \"formatVersion\": 1 }\n".utf8).write(to: settings)

        let reads = LockedCounter()
        let store = VaultStore(
            vaultRoot: vault.root, index: vault.index,
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            readFile: { url in
                if url.lastPathComponent == "vault.json" { reads.increment() }
                return try Data(contentsOf: url)
            })
        _ = try await store.addingEvent(on: date, text: "Su")
        #expect(reads.value == 1)

        try Data("{ \"formatVersion\": 2 }\n".utf8).write(to: settings)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: settings.path)

        await #expect(throws: VaultStoreError.readOnlyVault) {
            try await store.addingEvent(on: date, text: "Kitap")
        }
        #expect(reads.value == 2)

        await #expect(throws: VaultStoreError.readOnlyVault) {
            try await store.addingEvent(on: date, text: "Spor")
        }
        #expect(reads.value == 2)
    }

    @Test func transientReadFailureIsNotCachedAsReadOnly() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let date = CalendarDate("2026-10-04")!
        let settings = vault.root.appendingPathComponent(".app/vault.json")
        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ \"formatVersion\": 1 }\n".utf8).write(to: settings)

        let reads = LockedCounter()
        let store = VaultStore(
            vaultRoot: vault.root, index: vault.index,
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            readFile: { url in
                guard url.lastPathComponent == "vault.json" else { return try Data(contentsOf: url) }
                reads.increment()
                if reads.value == 1 { throw CocoaError(.fileReadNoSuchFile) }
                return try Data(contentsOf: url)
            })
        await #expect(throws: VaultStoreError.readOnlyVault) {
            try await store.addingEvent(on: date, text: "Su")
        }
        _ = try await store.addingEvent(on: date, text: "Kitap")
        #expect(reads.value == 2)
        #expect(try vault.bytes("journal/2026-10-04.md").count > 0)
    }

    @Test func missingVaultJSONAllowsWriteAsVersionOne() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let date = CalendarDate("2026-10-04")!
        _ = try await vault.store.addingEvent(on: date, text: "Su")
        #expect(try vault.bytes("journal/2026-10-04.md").count > 0)
    }

    @Test func journalCaseVariantBlocksWrite() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write("Journal/2026-10-04.md", "## Events\n- Eski\n")
        try vault.index.refresh(vaultRoot: vault.root)
        let date = CalendarDate("2026-10-04")!
        await #expect(throws: VaultStoreError.reservedFolderCaseMismatch(found: "Journal", expected: "journal")) {
            try await vault.store.addingEvent(on: date, text: "Yeni")
        }
        #expect(try vault.bytes("Journal/2026-10-04.md") == Data("## Events\n- Eski\n".utf8))
    }

    @Test func peopleCaseVariantAllowsJournalWrite() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "People/Baran.md",
            """
            ---
            type: person
            name: Baran
            ---
            """)
        try vault.index.refresh(vaultRoot: vault.root)
        let date = CalendarDate("2026-10-04")!
        _ = try await vault.store.addingEvent(on: date, text: "Su")
        #expect(try vault.bytes("journal/2026-10-04.md").count > 0)
    }

    @Test func peopleCaseVariantBlocksPersonCreation() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "People/Baran.md",
            """
            ---
            type: person
            name: Baran
            ---
            """)
        try vault.index.refresh(vaultRoot: vault.root)
        await #expect(throws: VaultStoreError.reservedFolderCaseMismatch(found: "People", expected: "people")) {
            try await vault.store.creatingEntity(kind: .person, name: "Deniz")
        }
    }

    @Test func peopleCaseVariantAllowsEditingExistingPerson() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "People/Baran.md",
            """
            ---
            type: person
            name: Baran
            ---
            """)
        try vault.index.refresh(vaultRoot: vault.root)
        _ = try await vault.store.settingFrontmatterValue(
            at: "People/Baran.md", key: "name", value: .text("Baran Kaya"))
        let document = try await vault.store.document(at: "People/Baran.md")
        guard case .parsed(let frontmatter) = document.frontmatter,
            case .scalar(let name) = frontmatter.field(named: "name")?.value
        else {
            Issue.record("expected parsed name field")
            return
        }
        #expect(name.text == "Baran Kaya")
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
