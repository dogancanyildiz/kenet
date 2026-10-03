import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

struct DayTests {
    @Test func newEventHasExactBytesAndIndex() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        #expect(vault.store.dayFilePath(for: storeDate) == storePath)
        let document = try await vault.store.addingEvent(
            on: storeDate, text: "[[Deniz Arıkan]]", time: LineClock(hour: 9, minute: 5))
        #expect(
            try vault.bytes()
                == Data(
                    "---\ntype: journal\ndate: 2026-09-27\n---\n\n## Events\n- 09:05 [[Deniz Arıkan]] ^aaaaaa\n".utf8))
        #expect(try await vault.store.dayDocument(for: storeDate) == document)
        #expect(try vault.index.blocks(on: storeDate).map(\.identifier) == ["aaaaaa"])
        #expect(try vault.index.unresolvedLinks().map(\.target) == ["Deniz Arıkan"])
        try vault.check()
    }

    @Test func newTaskHasExactBytesAndUninterpretedText() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.addingTask(on: storeDate, text: "Kitap 📅 2026-10-05 ⏫")
        #expect(
            try vault.bytes()
                == Data(
                    "---\ntype: journal\ndate: 2026-09-27\n---\n\n## Tasks\n- [ ] Kitap 📅 2026-10-05 ⏫ ^aaaaaa\n".utf8))
        #expect(try vault.index.blocks(on: storeDate).first?.status == "todo")
        try vault.check()
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func existingDayPreservesFrontmatterAndLineEndings(ending: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let before = "---\ntype: note\ncustom: 20.0290 # Su\n---\n\n## Events\n- Kitap ^old\n\n## Other\nDeniz"
            .replacingOccurrences(of: "\n", with: ending)
        try vault.write(storePath, before)
        try vault.index.refresh(vaultRoot: vault.root)
        try await vault.store.addingEvent(on: storeDate, text: "Su")
        let expected = before.replacingOccurrences(
            of: "- Kitap ^old" + ending, with: "- Kitap ^old" + ending + "- Su ^aaaaaa" + ending)
        #expect(try vault.bytes() == Data(expected.utf8))
        try vault.check()
    }

    @Test func frontmatterlessDayStaysFrontmatterless() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Events\n- Kitap ^old")
        try await vault.store.addingEvent(on: storeDate, text: "Su")
        #expect(try vault.bytes() == Data("## Events\n- Kitap ^old\n- Su ^aaaaaa\n".utf8))
        try vault.check()
    }

    @Test func sampleVaultOperationsMatchRebuild() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(sample: true, random: { random.next() })
        defer { vault.remove() }
        let date = CalendarDate("2026-09-14")!
        let before = try vault.bytes("journal/2026-09-14.md")
        let document = try await vault.store.addingEvent(on: date, text: "[[Deniz Arıkan]]")
        let expected = String(decoding: before, as: UTF8.self).replacingOccurrences(
            of: "\n\n## Journal", with: "\n- [[Deniz Arıkan]] ^aaaaaa\n\n## Journal")
        #expect(document.serialized() == Array(expected.utf8))
        #expect(
            try vault.index.links(to: "people/Deniz Arıkan.md").contains {
                $0.file == "journal/2026-09-14.md" && $0.target == "Deniz Arıkan"
            })
        try vault.check()
        try await vault.store.addingTask(on: date, text: "Kitap")
        try vault.check()
        try await vault.store.changingJournal(on: date, to: "Su\n### Kitap")
        try vault.check()
        let events = try await vault.store.dayDocument(for: date).bodyLines.events
        let changed = try await vault.store.changingText(
            of: events.last!.block, at: "journal/2026-09-14.md", to: "[[Selin Korkmaz]]")
        try vault.check()
        let timed = try await vault.store.changingTime(
            of: changed.bodyLines.events.last!, at: "journal/2026-09-14.md", to: LineClock(hour: 8, minute: 5))
        try vault.check()
        let completed = try await vault.store.changingStatus(
            of: timed.bodyLines.tasks.last!, at: "journal/2026-09-14.md", to: .done, completionDate: storeDate)
        try vault.check()
        try await vault.store.deletingBlock(completed.bodyLines.tasks.last!.block, at: "journal/2026-09-14.md")
        try vault.check()
    }
}
