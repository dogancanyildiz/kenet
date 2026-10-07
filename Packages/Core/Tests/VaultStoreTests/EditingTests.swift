import Foundation
import Testing
import VaultFormat
import VaultStore

struct EditingTests {
    @Test func identifierlessEditsReceiveIdentifiers() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: { random.next() })
        defer { vault.remove() }
        try vault.write(storePath, "## Tasks\n*  [ ] Kitap\n  Su\n\n## Events\n+  Deniz\n")
        let before = try await vault.store.dayDocument(for: storeDate)
        let status = try await vault.store.changingStatus(
            of: before.bodyLines.tasks[0], at: storePath, to: .done, completionDate: storeDate)
        #expect(status.bodyLines.tasks[0].block.id == "aaaaaa")
        #expect(
            try vault.bytes() == Data("## Tasks\n*  [x] Kitap ✅ 2026-09-27 ^aaaaaa\n  Su\n\n## Events\n+  Deniz\n".utf8)
        )
        try vault.check()
        let text = try await vault.store.changingText(of: status.bodyLines.events[0].block, at: storePath, to: "Selin")
        #expect(text.bodyLines.events[0].block.id == "bbbbbb")
        try vault.check()
        try vault.write(storePath, "## Events\n- Deniz\n")
        let event = try await vault.store.dayDocument(for: storeDate).bodyLines.events[0]
        let time = try await vault.store.changingTime(of: event, at: storePath, to: LineClock(hour: 9, minute: 5))
        #expect(time.bodyLines.events[0].block.id == "cccccc")
        try vault.check()
    }

    @Test func ownerKeepsIdentifierAndDuplicateGetsNewOne() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write("journal/2026-09-14.md", "## Events\n- Deniz ^duplicate\n")
        try vault.write(storePath, "## Events\n- Selin ^duplicate\n")
        try vault.index.refresh(vaultRoot: vault.root)
        let target = try await vault.store.dayDocument(for: storeDate).bodyLines.events[0].block
        let changed = try await vault.store.changingText(of: target, at: storePath, to: "Su")
        #expect(changed.bodyLines.events[0].block.id == "aaaaaa")
        let owner = try await vault.store.document(at: "journal/2026-09-14.md").bodyLines.events[0].block
        let retained = try await vault.store.changingText(of: owner, at: "journal/2026-09-14.md", to: "Kitap")
        #expect(retained.bodyLines.events[0].block.id == "duplicate")
        try vault.check()
    }

    @Test func sameDocumentDuplicateAndUnindexedIdentifiersAreChecked() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: { random.next() })
        defer { vault.remove() }
        try vault.write(storePath, "## Events\n- Deniz ^aaaaaa\n- Selin ^aaaaaa\n")
        let target = try await vault.store.dayDocument(for: storeDate).bodyLines.events[1].block
        let changed = try await vault.store.changingText(of: target, at: storePath, to: "Su")
        #expect(changed.bodyLines.events[1].block.id == "bbbbbb")
        try vault.check()
    }

    @Test func occupiedCandidatesRetryAndConstantRandomExhausts() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: { random.next() })
        defer { vault.remove() }
        try vault.write("notes/Kitap.md", "- [ ] Su ^aaaaaa\n")
        try vault.index.refresh(vaultRoot: vault.root)
        let changed = try await vault.store.addingEvent(on: storeDate, text: "Deniz")
        #expect(changed.bodyLines.events[0].block.id == "bbbbbb")
        let constant = VaultStore(vaultRoot: vault.root, index: vault.index, randomValue: { 0 })
        let before = try vault.bytes()
        await #expect(throws: EditError.identifierExhausted) {
            try await constant.addingTask(on: storeDate, text: "Kitap")
        }
        #expect(try vault.bytes() == before)
        try vault.check()
    }

    @Test func staleTargetsAreRejectedForEveryTargetedOperation() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Tasks\n- [ ] Kitap ^task\n## Events\n- Deniz ^event\n")
        let before = try await vault.store.dayDocument(for: storeDate)
        let task = before.bodyLines.tasks[0]
        let event = before.bodyLines.events[0]
        try vault.write(storePath, "## Tasks\n- [x] Su ^task\n## Events\n- Selin ^event\n")
        let bytes = try vault.bytes()
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.changingText(of: task.block, at: storePath, to: "Deniz")
        }
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.changingStatus(of: task, at: storePath, to: .done, completionDate: storeDate)
        }
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.changingTime(of: event, at: storePath, to: nil)
        }
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.deletingBlock(event.block, at: storePath)
        }
        #expect(try vault.bytes() == bytes)
    }

    @Test func deletionRetainsHeadingAndOutsideBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Tasks\n- [ ] Kitap\n  Su\n\n## Other\nDeniz\n")
        let target = try await vault.store.dayDocument(for: storeDate).bodyLines.tasks[0].block
        try await vault.store.deletingBlock(target, at: storePath)
        #expect(try vault.bytes() == Data("## Tasks\n\n## Other\nDeniz\n".utf8))
        try vault.check()
    }
}
