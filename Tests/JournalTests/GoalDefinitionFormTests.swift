import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// The definition form: one "Kaydet" for the whole definition, only changed fields written.
@MainActor
struct GoalDefinitionFormTests {
    private func goal(_ context: TaskTestContext, _ path: String) async throws -> GoalDefinition {
        try #require(try await context.store.goalDefinitions().first { $0.id == path })
    }

    /// The form's model as the sheet opens it: the other goals' names loaded.
    private func definitionModel(_ context: TaskTestContext, _ path: String) async throws -> GoalDefinitionModel {
        let model = GoalDefinitionModel(store: context.store, goal: try await goal(context, path))
        await model.load()
        return model
    }

    private func text(_ file: URL) throws -> String { String(decoding: try Data(contentsOf: file), as: UTF8.self) }

    @Test func saveWritesOnlyChangedFieldsAndKeepsFileName() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("goals/Su.md")
        let before = try text(file)
        let model = try await definitionModel(context, "goals/Su.md")
        var draft = GoalDefinitionDraft(goal: model.goal)
        #expect(draft.target == "8")
        draft.target = "8,0"
        #expect(model.changes(in: draft).isEmpty, "the same amount in another spelling is no change")
        #expect(!model.canSave(draft))
        draft.target = "10"
        #expect(model.changes(in: draft) == [GoalDefinitionChange(field: .target, text: "10")])
        #expect(await model.apply(draft))
        #expect(try text(file) == before.replacingOccurrences(of: "target: 8\n", with: "target: 10\n"))

        let renamed = try await definitionModel(context, "goals/Su.md")
        var second = GoalDefinitionDraft(goal: renamed.goal)
        second.name = "  İçecek "
        second.unit = ""
        #expect(renamed.changes(in: second).map(\.field) == [.name, .unit])
        #expect(await renamed.apply(second))
        let expected = before.replacingOccurrences(of: "target: 8\n", with: "target: 10\n")
            .replacingOccurrences(of: "name: Su\n", with: "name: İçecek\n")
            .replacingOccurrences(of: "unit: bardak\n", with: "")
        #expect(try text(file) == expected)
        let changed = try await goal(context, "goals/Su.md")
        #expect(changed.name == "İçecek" && changed.key == "su" && changed.target == 10 && changed.unit == nil)
        #expect(!FileManager.default.fileExists(atPath: context.root.appendingPathComponent("goals/İçecek.md").path))
    }

    @Test func invalidFieldShowsItsErrorAndNothingIsWritten() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("goals/Kitap.md")
        let before = try Data(contentsOf: file)
        let model = try await definitionModel(context, "goals/Kitap.md")
        var draft = GoalDefinitionDraft(goal: model.goal)
        draft.name = "Okuma"
        #expect(model.error(for: .name, in: draft) == nil)
        for amount in ["0", "-1", "abc", "nan", "1e3", ""] {
            draft.target = amount
            #expect(model.error(for: .target, in: draft) != nil, "\(amount)")
            #expect(model.error(for: .name, in: draft) == nil)
            #expect(!model.canSave(draft))
            #expect(await !model.apply(draft))
        }
        #expect(try Data(contentsOf: file) == before, "a valid name is not written beside an invalid amount")
        draft.target = "20"
        draft.name = "SPOR"
        #expect(model.error(for: .name, in: draft) == String(localized: "Bu ad zaten kullanılıyor. Başka bir ad seç."))
        draft.name = "   "
        #expect(model.error(for: .name, in: draft) != nil)
        #expect(await !model.apply(draft))
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func milestoneKeepsPeriodAndKind() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let file = context.root.appendingPathComponent("goals/Yayın.md")
        let source = "---\ntype: goal\nname: Yayın\nkey: yayin\nperiod: year\nkind: milestone\n---\n"
        try Data(source.utf8).write(to: file)
        await context.start()
        let milestone = try await definitionModel(context, "goals/Yayın.md")
        #expect(milestone.isScheduleLocked)
        #expect(try await !definitionModel(context, "goals/Su.md").isScheduleLocked)
        var draft = GoalDefinitionDraft(goal: milestone.goal)
        draft.period = .day
        draft.kind = .number
        draft.target = "5"
        #expect(milestone.changes(in: draft).isEmpty)
        #expect(await !milestone.apply(draft))
        #expect(try text(file) == source)
        draft.name = "İlk yayın"
        #expect(milestone.changes(in: draft).map(\.field) == [.name])
        #expect(await milestone.apply(draft))
        #expect(try text(file) == source.replacingOccurrences(of: "name: Yayın\n", with: "name: İlk yayın\n"))
        let saved = try await goal(context, "goals/Yayın.md")
        #expect(saved.kind == .milestone && saved.period == .year)
    }

    @Test func dirtyDraftAsksBeforeClosing() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = try await definitionModel(context, "goals/Spor.md")
        func asks(_ draft: GoalDefinitionDraft, saving: Bool = false) -> Bool {
            UnsavedDraftDecision.requiresPrompt(isDirty: !model.changes(in: draft).isEmpty, isSaving: saving)
        }
        var draft = GoalDefinitionDraft(goal: model.goal)
        #expect(!asks(draft))
        draft.name = "Spor "
        #expect(!asks(draft), "surrounding spaces are not a change")
        draft.name = "Koşu"
        #expect(asks(draft))
        #expect(!asks(draft, saving: true))
        draft.name = "Spor"
        draft.period = .day
        #expect(asks(draft))
        draft.period = .week
        draft.target = "3.0"
        #expect(!asks(draft))
    }

    @Test func deletingFromTheFormRemovesTheFileAndALaterSaveDoesNotBringItBack() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let path = "goals/Spor.md"
        let file = context.root.appendingPathComponent(path)
        let model = try await definitionModel(context, path)
        var draft = GoalDefinitionDraft(goal: model.goal)
        draft.target = "4"
        let deletion = DefinitionDeletionModel()
        deletion.request(path: model.goal.id)
        let confirmedPath = deletion.confirmation.confirm()
        let confirmed = try #require(confirmedPath)
        #expect(confirmed == path)
        #expect(await deletion.delete(store: context.store, path: confirmed, goal: true))
        #expect(deletion.isDeleted)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect((try await context.store.goalDefinitions()).allSatisfy { $0.id != path })
        #expect(await !model.apply(draft))
        #expect(model.errorText != nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func oneSaveIsOneWriteTurnAndOneIndexUpdate() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("goals/Su.md")
        let before = try text(file)
        let model = try await definitionModel(context, "goals/Su.md")
        var draft = GoalDefinitionDraft(goal: model.goal)
        draft.name = "İçecek"
        draft.target = "10"
        draft.unit = "kupa"
        #expect(model.changes(in: draft).map(\.field) == [.name, .target, .unit])
        var turns = 0
        context.store.testingEditTurnDidArrive = { turns += 1 }
        #expect(await model.apply(draft))
        context.store.testingEditTurnDidArrive = nil
        #expect(turns == 1, "three fields, one write turn")
        let expected = before.replacingOccurrences(of: "name: Su\n", with: "name: İçecek\n")
            .replacingOccurrences(of: "target: 8\n", with: "target: 10\n")
            .replacingOccurrences(of: "unit: bardak\n", with: "unit: kupa\n")
        #expect(try text(file) == expected)
        let saved = try await goal(context, "goals/Su.md")
        #expect(saved.name == "İçecek" && saved.target == 10 && saved.unit == "kupa")
    }

    @Test func fileChangedBeforeTheWriteTurnIsNotWritten() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("goals/Su.md")
        let model = try await definitionModel(context, "goals/Su.md")
        var draft = GoalDefinitionDraft(goal: model.goal)
        draft.name = "İçecek"
        draft.target = "10"
        // Another app gives the file another key after "Kaydet" but before the write turn.
        let other = "---\ntype: goal\nname: Su\nkey: baska\nperiod: day\nkind: number\ntarget: 8\n---\n"
        let store = context.store
        store.testingEditTurnDidArrive = {
            store.testingEditTurnDidArrive = nil
            try? Data(other.utf8).write(to: file)
        }
        #expect(await !model.apply(draft))
        #expect(try text(file) == other)
        #expect(model.errorText == DayEditError.message(for: VaultStoreError.staleTarget))
    }

    @Test func failureAfterTheFirstFieldKeepsTheFormOpenWithTheReason() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let file = context.root.appendingPathComponent("goals/Yudum.md")
        // A block scalar is a raw field: the app reads no unit and never rewrites its lines.
        let source =
            "---\ntype: goal\nname: Yudum\nkey: yudum\nperiod: day\nkind: number\ntarget: 4\nunit: |\n  bardak\n---\n"
        try Data(source.utf8).write(to: file)
        await context.start()
        let model = try await definitionModel(context, "goals/Yudum.md")
        #expect(model.goal.unit == nil)
        var draft = GoalDefinitionDraft(goal: model.goal)
        draft.name = "Yudum su"
        draft.unit = "kupa"
        #expect(model.changes(in: draft).map(\.field) == [.name, .unit])
        #expect(model.canSave(draft))
        #expect(await !model.apply(draft), "the form stays open")
        #expect(model.errorText != nil)
        #expect(!model.isWriting)
        #expect(try text(file) == source.replacingOccurrences(of: "name: Yudum\n", with: "name: Yudum su\n"))
        #expect(try await goal(context, "goals/Yudum.md").name == "Yudum su", "the written field reaches the index")
    }

    @Test func hiddenUnitIsNotWritten() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("goals/Spor.md")
        let before = try text(file)
        let model = try await definitionModel(context, "goals/Spor.md")
        var draft = GoalDefinitionDraft(goal: model.goal)
        #expect(!model.showsUnit(draft))
        draft.kind = .number
        draft.unit = "tur"
        #expect(model.showsUnit(draft))
        #expect(model.changes(in: draft).map(\.field) == [.kind, .unit])
        draft.kind = .boolean
        #expect(!model.showsUnit(draft))
        #expect(model.changes(in: draft).isEmpty, "a unit typed in a field now hidden is no change")
        draft.name = "Koşu"
        #expect(await model.apply(draft))
        #expect(try text(file) == before.replacingOccurrences(of: "name: Spor\n", with: "name: Koşu\n"))
        let kitap = try await definitionModel(context, "goals/Kitap.md")
        var shown = GoalDefinitionDraft(goal: kitap.goal)
        shown.kind = .boolean
        #expect(kitap.showsUnit(shown), "a unit in the file stays on the form")
    }
}
