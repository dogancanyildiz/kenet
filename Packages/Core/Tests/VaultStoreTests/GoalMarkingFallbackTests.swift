import Foundation
import GRDB
import GoalTracking
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

struct GoalMarkingFallbackTests {
    @Test func settingGoalValueSucceedsWhenGoalsIsSymlinkToDirectory() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "Real/Spor.md",
            """
            ---
            type: goal
            name: Spor
            key: spor
            period: day
            kind: boolean
            target: 1
            ---

            """)
        try FileManager.default.createSymbolicLink(
            at: vault.root.appendingPathComponent("goals"),
            withDestinationURL: vault.root.appendingPathComponent("Real"))
        try vault.index.rebuild(vaultRoot: vault.root)

        try await vault.store.settingGoalValue(on: storeDate, key: "spor", value: .boolean(true))
        let document = try await vault.store.dayDocument(for: storeDate)
        guard case .parsed(let fields) = document.frontmatter,
            case .mapping(let entries) = fields.field(named: "goals")?.value,
            case .boolean(true) = entries.first(where: { $0.key == "spor" })?.value.kind
        else {
            Issue.record("Expected spor: true in day frontmatter")
            return
        }
    }

    @Test func settingGoalValueSucceedsWhenGoalsIsRegularFile() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "Real/Spor.md",
            """
            ---
            type: goal
            name: Spor
            key: spor
            period: day
            kind: boolean
            target: 1
            ---

            """)
        try Data("not-a-directory\n".utf8).write(to: vault.root.appendingPathComponent("goals"))
        try vault.index.rebuild(vaultRoot: vault.root)

        try await vault.store.settingGoalValue(on: storeDate, key: "spor", value: .boolean(true))
        let document = try await vault.store.dayDocument(for: storeDate)
        guard case .parsed(let fields) = document.frontmatter,
            case .mapping(let entries) = fields.field(named: "goals")?.value,
            case .boolean(true) = entries.first(where: { $0.key == "spor" })?.value.kind
        else {
            Issue.record("Expected spor: true in day frontmatter")
            return
        }
    }

    @Test func staleIndexStillRejectsSecondMilestoneInYear() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "goals/Proje.md",
            """
            ---
            type: goal
            name: Proje
            key: proje
            period: year
            kind: milestone
            ---

            """)
        try vault.write(
            "journal/2026-03-01.md",
            """
            ---
            type: journal
            date: 2026-03-01
            goals:
              proje: true
            ---

            """)
        try vault.index.rebuild(vaultRoot: vault.root)
        try FileManager.default.createDirectory(
            at: vault.root.appendingPathComponent("Archive"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: vault.root.appendingPathComponent("goals/Proje.md"),
            to: vault.root.appendingPathComponent("Archive/Proje.md"))

        await #expect(throws: EditError.invalidValue) {
            try await vault.store.settingGoalValue(on: storeDate, key: "proje", value: .boolean(true))
        }
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(storePath).path))
    }

    @Test func goalFilesFailureFallsBackToFullScanForMilestoneCheck() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "Archive/Proje.md",
            """
            ---
            type: goal
            name: Proje
            key: proje
            period: year
            kind: milestone
            ---

            """)
        try vault.write(
            "journal/2026-03-01.md",
            """
            ---
            type: journal
            date: 2026-03-01
            goals:
              proje: true
            ---

            """)
        try vault.index.rebuild(vaultRoot: vault.root)
        try await vault.index.database.write { try $0.execute(sql: "DROP TABLE entities") }

        await #expect(throws: EditError.invalidValue) {
            try await vault.store.settingGoalValue(on: storeDate, key: "proje", value: .boolean(true))
        }
    }

    @Test func dualDefinitionOutsideGoalsFallsBackWhenSecondIsUnindexedMilestone() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "Archive/Proje.md",
            """
            ---
            type: goal
            name: Proje
            key: proje
            period: year
            kind: boolean
            target: 1
            ---

            """)
        try vault.write(
            "journal/2026-03-01.md",
            """
            ---
            type: journal
            date: 2026-03-01
            goals:
              proje: true
            ---

            """)
        try vault.index.rebuild(vaultRoot: vault.root)
        try vault.write(
            "Extra/Proje.md",
            """
            ---
            type: goal
            name: Proje Kopya
            key: proje
            period: year
            kind: milestone
            ---

            """)

        await #expect(throws: EditError.invalidValue) {
            try await vault.store.settingGoalValue(on: storeDate, key: "proje", value: .boolean(true))
        }
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(storePath).path))
    }
}
