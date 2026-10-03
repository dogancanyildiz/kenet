import Foundation
import Testing
import VaultFormat

struct OwnershipRegressionTests {
    @Test func staleIndexLineNumbersDoNotChangeOwnerIdentifier() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Events\n- Deniz ^keepme\n")
        try vault.index.refresh(vaultRoot: vault.root)
        try vault.write(storePath, "## Events\n- Selin\n- Deniz ^keepme\n")
        let target = try await vault.store.dayDocument(for: storeDate).bodyLines.events[1].block
        let changed = try await vault.store.changingText(of: target, at: storePath, to: "Su")
        #expect(changed.bodyLines.events[1].block.id == "keepme")
        #expect(try vault.bytes() == Data("## Events\n- Selin\n- Su ^keepme\n".utf8))
        try vault.check()
    }

    @Test func freshlyReorderedDuplicatesUseFirstOccurrence() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: { random.next() })
        defer { vault.remove() }
        try vault.write(storePath, "## Events\n- Deniz ^keepme\n- Selin ^keepme\n")
        try vault.index.refresh(vaultRoot: vault.root)
        try vault.write(storePath, "## Events\n- Kitap\n- Selin ^keepme\n- Deniz ^keepme\n")
        let document = try await vault.store.dayDocument(for: storeDate)
        let first = try await vault.store.changingText(of: document.bodyLines.events[1].block, at: storePath, to: "Su")
        #expect(first.bodyLines.events[1].block.id == "keepme")
        let second = try await vault.store.changingText(of: first.bodyLines.events[2].block, at: storePath, to: "Kitap")
        #expect(second.bodyLines.events[2].block.id == "aaaaaa")
        try vault.check()
    }

    @Test func unindexedTaskIdentifierIsExcludedFromEventCandidates() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: { random.next() })
        defer { vault.remove() }
        try vault.write(storePath, "## Tasks\n- [ ] Kitap ^aaaaaa\n")
        #expect(try vault.index.blockIdentifiers().isEmpty)
        let changed = try await vault.store.addingEvent(on: storeDate, text: "Su")
        #expect(changed.bodyLines.events[0].block.id == "bbbbbb")
        #expect(changed.bodyLines.tasks[0].block.id == "aaaaaa")
        try vault.check()
    }

    @Test func ownerQueryIgnoresEarlierInsertedNonOwner() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        // Insert the later path first so its non-owner row precedes the actual owner's row in SQLite.
        try vault.write(storePath, "## Events\n- Selin ^keepme\n")
        try vault.index.refresh(vaultRoot: vault.root)
        try vault.write("journal/2026-09-14.md", "## Events\n- Deniz ^keepme\n")
        try vault.index.refresh(vaultRoot: vault.root)
        let owner = try #require(try vault.index.owner(of: "keepme"))
        #expect(owner.ownsIdentifier)
        #expect(owner.file == "journal/2026-09-14.md")
        let target = try await vault.store.dayDocument(for: storeDate).bodyLines.events[0].block
        let changed = try await vault.store.changingText(of: target, at: storePath, to: "Su")
        #expect(changed.bodyLines.events[0].block.id == "aaaaaa")
        try vault.check()
    }
}
