import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

@MainActor
struct GoalDefinitionTests {
    @Test func automaticKeysSimplifyTurkishAndReserveSuffixes() {
        #expect(VaultStore.goalKey(for: "Su İçme") == "su-icme")
        #expect(VaultStore.goalKey(for: "ÇĞıÖŞÜ İ") == "cgiosu-i")
        #expect(VaultStore.goalKey(for: "  Su---İçme  ") == "su-icme")
        #expect(VaultStore.goalKey(for: "Su İçme", reserving: ["SU-ICME", "su-icme-2"]) == "su-icme-3")
        #expect(VaultStore.goalKey(for: "!!!") == "goal")
    }

    @Test func creationPublishesDefinitionAndExactFixtureBytes() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = GoalCreationModel(store: context.store)
        model.name = "Su İçme"
        #expect(model.canSave && model.key == "su-icme")
        #expect(await model.save())
        #expect(await !model.save())
        let file = context.store.vaultURL!.appendingPathComponent("goals/Su İçme.md")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/goals/creation/boolean-expected.md")
        #expect(try Data(contentsOf: file) == Data(contentsOf: fixture))
        let goal = try #require(context.store.content.goals.first)
        #expect(goal.key == "su-icme" && goal.period == .day && goal.kind == .boolean)
        #expect(context.store.content.reservedGoalKeys.contains(goal.key))
    }

    @Test func collidingNameDoesNotOverwriteAndCanBeCorrected() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("goals/Spor.md")
        let before = try Data(contentsOf: file)
        let model = GoalCreationModel(store: context.store)
        model.name = "SPOR"
        #expect(await !model.save())
        #expect(model.errorText != nil && !model.isSaved)
        #expect(try Data(contentsOf: file) == before)
        model.name = "Yeni Spor"
        model.period = .week
        model.target = "3"
        #expect(await model.save())
        #expect(context.store.content.goals.contains { $0.key == "yeni-spor" })
    }

    @Test func definitionEditingKeepsKeyPathUnknownFieldsAndNotes() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("goals/Su.md")
        let source =
            "---\ntype: goal\nname: Su\nkey: su\nperiod: day\nkind: number\ntarget: 8 # keep\nunit: bardak\ncustom: 20.0290\n---\n\nKeep notes\n"
        try Data(source.utf8).write(to: file)
        await context.store.refresh()
        let goal = try #require(context.store.content.goals.first { $0.key == "su" })
        let model = GoalDefinitionModel(store: context.store, goal: goal)
        #expect(await model.set("target", text: "10"))
        #expect(
            try Data(contentsOf: file) == Data(source.replacingOccurrences(of: "target: 8", with: "target: 10").utf8))
        #expect(await model.set("name", text: "İçecek"))
        #expect(await model.set("period", text: "week"))
        #expect(await model.set("kind", text: "boolean"))
        #expect(await model.set("unit", text: ""))
        #expect(await !model.set("key", text: "new-key"))
        let changed = try #require(context.store.content.goals.first { $0.id == "goals/Su.md" })
        #expect(
            changed.name == "İçecek" && changed.key == "su" && changed.period == .week && changed.kind == .boolean
                && changed.unit == nil)
        let result = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(result.contains("custom: 20.0290\n") && result.hasSuffix("\nKeep notes\n"))
        for text in ["0", "-1", "nan", "invalid"] { #expect(await !model.set("target", text: text)) }
    }

    @Test func modelsRefuseEditsAfterVaultSwitch() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = GoalDayModel(store: context.store, day: context.today)
        await day.load()
        let goal = try #require(day.goals.first)
        let creation = GoalCreationModel(store: context.store)
        creation.name = "New"
        let definition = GoalDefinitionModel(store: context.store, goal: goal)
        let other = context.directory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        #expect(!day.canEdit && !creation.canSave && !definition.canEdit)
        #expect(await !day.set(goal, value: .number(20)))
        #expect(await !creation.save())
        #expect(await !definition.set("name", text: "New"))
    }
}
