import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

struct IncrementalReadModelTests {
    @Test func fullBuildMatchesSnapshotInit() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let fromSnapshot = try IncrementalReadModelVault.fullModel(index: index)
        let fromIndex = try VaultReadModel(index: index, today: IncrementalReadModelVault.today)
        #expect(fromSnapshot.matchesScreenFields(fromIndex))
        let fileCount = try index.files().count
        #expect(fromSnapshot.fragments.count == fileCount)
    }

    @Test func addingEventMatchesFullRebuild() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let previous = try IncrementalReadModelVault.fullModel(index: index)

        let store = VaultStore(vaultRoot: root, index: index)
        _ = try await store.addingEvent(
            on: IncrementalReadModelVault.today, text: "Wrote after lunch", time: nil)
        let day = "journal/\(IncrementalReadModelVault.today).md"
        let incremental = try VaultPublishedContent.applying(
            previous: previous, index: index, changedPaths: [day], today: IncrementalReadModelVault.today
        ).content
        let full = try IncrementalReadModelVault.fullModel(index: index)
        #expect(incremental.matchesScreenFields(full))
        #expect(incremental.days.contains { $0.events.contains { $0.text.plainText.contains("Wrote after lunch") } })
    }

    @Test func completingTaskMatchesFullRebuild() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let previous = try IncrementalReadModelVault.fullModel(index: index)
        let store = VaultStore(vaultRoot: root, index: index)
        let path = "journal/\(IncrementalReadModelVault.today).md"
        let document = try await store.document(at: path)
        let task = try #require(document.bodyLines.tasks.first { $0.block.id == "task1" })
        _ = try await store.changingStatus(
            of: task, at: path, to: .done, completionDate: IncrementalReadModelVault.today)

        let incremental = try VaultPublishedContent.applying(
            previous: previous, index: index, changedPaths: [path],
            today: IncrementalReadModelVault.today
        ).content
        let full = try IncrementalReadModelVault.fullModel(index: index)
        #expect(incremental.matchesScreenFields(full))
        #expect(incremental.tasks.first { $0.sourceIdentifier == "task1" }?.isClosed == true)
    }

    @Test func deletingFileMatchesFullRebuild() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let previous = try IncrementalReadModelVault.fullModel(index: index)

        try FileManager.default.removeItem(at: root.appendingPathComponent("notes/Scratch.md"))
        let result = try index.refresh(vaultRoot: root)
        #expect(result.deletedPaths == ["notes/Scratch.md"])

        let incremental = try IncrementalReadModelVault.apply(previous, index: index, result: result)
        let full = try IncrementalReadModelVault.fullModel(index: index)
        #expect(incremental.matchesScreenFields(full))
        #expect(!incremental.tasks.contains { $0.file == "notes/Scratch.md" })
    }

    @Test func renamingEntityMatchesFullRebuild() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let previous = try IncrementalReadModelVault.fullModel(index: index)
        let store = VaultStore(vaultRoot: root, index: index)
        let renamed = try await store.renamingEntity(at: "people/Deniz Example.md", to: "Deniz Renamed")
        var changed = Set(renamed.updatedFiles)
        changed.insert(renamed.path)
        changed.insert("people/Deniz Example.md")

        let incremental = try VaultPublishedContent.applying(
            previous: previous, index: index, changedPaths: changed,
            deletedPaths: ["people/Deniz Example.md"], today: IncrementalReadModelVault.today
        ).content
        let full = try IncrementalReadModelVault.fullModel(index: index)
        #expect(incremental.matchesScreenFields(full))
        #expect(incremental.entities.contains { $0.name == "Deniz Renamed" })
        #expect(!incremental.entities.contains { $0.id == "people/Deniz Example.md" })
    }

    @Test func externalDayEditMatchesFullRebuild() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let previous = try IncrementalReadModelVault.fullModel(index: index)

        let path = "journal/2026-10-04.md"
        var text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        text += "\nExtra external paragraph.\n"
        try Data(text.utf8).write(to: root.appendingPathComponent(path))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: root.appendingPathComponent(path).path)

        let result = try index.refresh(vaultRoot: root)
        #expect(result.updatedPaths.contains(path))
        let incremental = try IncrementalReadModelVault.apply(previous, index: index, result: result)
        let full = try IncrementalReadModelVault.fullModel(index: index)
        #expect(incremental.matchesScreenFields(full))
        #expect(
            incremental.days.first { $0.id == path }?.journal.contains {
                $0.text.plainText.contains("Extra external paragraph")
            } == true)
    }

    @Test func creatingPersonResolvesExistingLinks() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        try IncrementalReadModelVault.write(
            root, "journal/2026-10-03.md",
            """
            ---
            type: journal
            date: 2026-10-03
            ---
            ## Events
            - 11:00 Met [[Zora Example]] ^z1
            """)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let previous = try IncrementalReadModelVault.fullModel(index: index)
        #expect(previous.entities.allSatisfy { $0.name != "Zora Example" })

        let store = VaultStore(vaultRoot: root, index: index)
        _ = try await store.creatingEntity(kind: .person, name: "Zora Example", qualifier: nil)

        let incremental = try VaultPublishedContent.applying(
            previous: previous, index: index, changedPaths: ["people/Zora Example.md"],
            today: IncrementalReadModelVault.today
        ).content
        let full = try IncrementalReadModelVault.fullModel(index: index)
        #expect(incremental.matchesScreenFields(full))
        let zora = try #require(incremental.entities.first { $0.name == "Zora Example" })
        #expect(zora.incomingLinks >= 1)
        #expect(incremental.entityTimeline[zora.id] != nil)
    }
}
