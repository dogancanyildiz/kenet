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

    @Test func guessedGoalPathReconcilesUsingWriterPath() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let previous = try IncrementalReadModelVault.fullModel(index: index)

        let store = VaultStore(vaultRoot: root, index: index)
        let actual = try await store.creatingGoal(
            name: "Koşu: 5 km", period: .day, kind: .number, target: 5, unit: "km")
        let guessed = "goals/Koşu: 5 km.md"
        #expect(actual == "goals/Koşu 5 km.md")
        #expect(guessed != actual)

        // Store used to publish the unsanitized guess; the safety net must still match a full build.
        let incremental = try VaultPublishedContent.applying(
            previous: previous, index: index, changedPaths: [guessed],
            estimatedPaths: [guessed], today: IncrementalReadModelVault.today
        ).content
        let full = try IncrementalReadModelVault.fullModel(index: index)
        #expect(incremental.matchesScreenFields(full))
        #expect(incremental.goals.contains { $0.name == "Koşu: 5 km" })
        #expect(!incremental.needsFullReconcile)
    }

    @Test func dayChangeRederivesGoalStatuses() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let dayBuilt = CalendarDate("2026-10-05")!
        let nextDay = CalendarDate("2026-10-06")!
        let previous = try IncrementalReadModelVault.fullModel(index: index, today: dayBuilt)
        #expect(previous.derivedForDay == dayBuilt)

        // Touch a day file that has no goal logs so patch would otherwise skip goalStatuses.
        let untouchedGoalsDay = CalendarDate("2026-10-04")!
        let store = VaultStore(vaultRoot: root, index: index)
        _ = try await store.addingEvent(on: untouchedGoalsDay, text: "After midnight note", time: nil)
        let dayPath = "journal/\(untouchedGoalsDay).md"

        let incremental = try VaultPublishedContent.applying(
            previous: previous, index: index, changedPaths: [dayPath], today: nextDay
        ).content
        let full = try IncrementalReadModelVault.fullModel(index: index, today: nextDay)
        #expect(incremental.matchesScreenFields(full))
        #expect(incremental.derivedForDay == nextDay)
        #expect(incremental.goalStatuses != previous.goalStatuses)
    }

    @Test func daySortTieBreakMatchesFullDerive() {
        let day = CalendarDate("2026-10-04")!
        let earlier = DaySummary(id: "journal/a.md", date: day, events: [], journal: [])
        let later = DaySummary(id: "journal/b.md", date: day, events: [], journal: [])
        // Full derive walks path-sorted files then sorts by date (stable → path on ties).
        let full = [earlier, later].sorted(by: VaultReadModel.daySort)
        // Patch removes the path-earlier day and re-appends it last.
        var incremental = [later, earlier]
        incremental.sort(by: VaultReadModel.daySort)
        #expect(incremental.map(\.id) == full.map(\.id))
        #expect(incremental.map(\.id) == ["journal/a.md", "journal/b.md"])
        // Date-only sort would keep the reversed patch order.
        var dateOnly = [later, earlier]
        dateOnly.sort { $0.date > $1.date }
        #expect(dateOnly.map(\.id) == ["journal/b.md", "journal/a.md"])
    }

    @Test func goalTouchedKeepsInvalidDefinitionKeys() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        // Invalid milestone (day period) still indexes a goalKey that must stay reserved.
        try IncrementalReadModelVault.write(
            root, "goals/Broken Milestone.md",
            """
            ---
            type: goal
            name: Broken Milestone
            key: broken-milestone
            period: day
            kind: milestone
            ---
            """)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let previous = try IncrementalReadModelVault.fullModel(index: index)
        #expect(previous.goals.allSatisfy { $0.key != "broken-milestone" })
        #expect(previous.reservedGoalKeys.contains("broken-milestone"))

        var text = try String(contentsOf: root.appendingPathComponent("journal/2026-10-05.md"), encoding: .utf8)
        text = text.replacingOccurrences(of: "reading: 5", with: "reading: 6")
        try Data(text.utf8).write(to: root.appendingPathComponent("journal/2026-10-05.md"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: root.appendingPathComponent("journal/2026-10-05.md").path)
        let result = try index.refresh(vaultRoot: root)

        let incremental = try IncrementalReadModelVault.apply(previous, index: index, result: result)
        let full = try IncrementalReadModelVault.fullModel(index: index)
        #expect(incremental.matchesScreenFields(full))
        #expect(incremental.reservedGoalKeys.contains("broken-milestone"))
    }
}
