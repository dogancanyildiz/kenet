import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// An edit belongs to the vault selected when it was asked for. A vault selected while the edit
/// waited for its turn is never written, whatever the edit is.
@MainActor
struct EditVaultTurnTests {
    /// Every `IndexStore` write path: the shared `performEdit` and the three that hold the write slot
    /// themselves.
    enum Edit: String, CaseIterable, Sendable {
        case addEvent, completeTask, appendToJournal, renameEntity, createEntity
    }

    private static let day =
        "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Tasks\n- [ ] süt al ^sut\n\n## Journal\nEski.\n"
    private static let person = "---\ntype: person\nname: Ada Kurgu\n---\n"

    @Test(arguments: Edit.allCases)
    func aVaultSelectedWhileTheEditWaitsIsNotWritten(_ edit: Edit) async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        for (path, text) in ["journal/2026-10-03.md": Self.day, "people/Ada Kurgu.md": Self.person] {
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        await context.store.refresh()
        // The other vault holds the very same files, so only the vault check can refuse the write.
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.copyItem(at: context.root, to: other)
        let store = context.store
        let row = try await context.row("süt al")
        let before = try Self.files(context.root)
        let otherBefore = try Self.files(other)
        var switched = false
        store.testingEditTurnDidArrive = {
            store.testingEditTurnDidArrive = nil
            await store.select(other)
            switched = true
        }

        if edit == .addEvent {
            // The quick entry keeps its draft on `false` and shows the stale-target message.
            #expect(!(await store.addEvent(on: context.today, text: "Yanlış kasa.", time: nil)))
            #expect(store.entryErrorText == EntryWriteError.message(for: VaultStoreError.staleTarget))
        } else {
            await #expect(throws: VaultStoreError.staleTarget) {
                switch edit {
                case .addEvent: break
                case .completeTask: try await store.completeTask(row, on: context.today)
                case .appendToJournal:
                    try await store.appendToJournal(on: context.today, lines: ["Yanlış kasa."])
                case .renameEntity:
                    _ = try await store.renameEntity(at: "people/Ada Kurgu.md", to: "Ada Yanlış", qualifier: nil)
                case .createEntity:
                    _ = try await store.createEntity(kind: .person, name: "Yanlış Kasa", qualifier: nil)
                }
            }
        }

        #expect(switched)
        #expect(store.vaultURL.map(Self.canonical) == Self.canonical(other))
        #expect(try Self.files(context.root) == before)
        #expect(try Self.files(other) == otherBefore)
        #expect(store.canAddEvent)
    }

    private static func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    private static func files(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let prefix = canonical(root) + "/"
        let found = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in found {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            result[String(canonical(url).dropFirst(prefix.count))] = try Data(contentsOf: url)
        }
        return result
    }
}
