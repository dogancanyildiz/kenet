import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct GoalTemplateTests {
    private let turkish = Locale(identifier: "tr_TR")
    private let english = Locale(identifier: "en_US")

    private func template(_ id: String) throws -> GoalTemplate {
        try #require(GoalTemplate.all.first { $0.id == id })
    }

    @Test func catalogHasExactlyTheApprovedOrderAndUniqueIdentities() {
        #expect(GoalTemplate.all.count == 15)
        #expect(Set(GoalTemplate.all.map(\.id)).count == 15)
        #expect(
            GoalTemplate.all.map(\.id) == [
                "water", "read", "exercise", "walk", "meditate", "wake", "vitamins", "floss",
                "nosmoking", "nosugar", "language", "sleep", "tidy", "nospend", "gym",
            ])
        #expect(GoalTemplate.all.map(\.target) == [8, 20, 30, 10000, 10, 1, 1, 1, 1, 1, 15, 8, 10, 1, 3])
        #expect(GoalTemplate.all.filter { $0.period == .week }.map(\.id) == ["gym"])
        #expect(GoalTemplate.all.filter { $0.period == .day }.count == 14)
        #expect(
            GoalTemplate.all.filter { $0.kind == .number }.map(\.id) == [
                "water", "read", "exercise", "walk", "meditate", "language", "sleep", "tidy",
            ])
    }

    @Test(arguments: GoalTemplate.all)
    func templatesHaveValidAmountsAndUnits(_ template: GoalTemplate) {
        #expect(template.target > 0)
        #expect(!template.symbol.isEmpty)
        if template.kind == .number {
            #expect(template.unit?.isEmpty == false)
        } else {
            #expect(template.kind == .boolean)
            #expect(template.unit == nil)
        }
    }

    @Test(arguments: GoalTemplate.all)
    func applyingReplacesEveryFieldAndEnablesSave(_ template: GoalTemplate) async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = GoalCreationModel(store: context.store)
        model.name = "Önceki taslak"
        model.kind = .milestone
        model.period = .year
        model.target = "99"
        model.unit = "eski birim"
        #expect(model.templateID == nil)
        model.apply(template, locale: turkish)
        #expect(model.templateID == template.id)
        #expect(model.name == template.localizedName(locale: turkish))
        #expect(model.kind == template.kind)
        #expect(model.period == template.period)
        #expect(model.target == String(template.target))
        #expect(model.unit == template.localizedUnit(locale: turkish) ?? "")
        #expect(model.canSave)
        model.name = "Düzenlenmiş hedef"
        model.period = .year
        model.target = "7"
        model.unit = "tur"
        #expect(model.templateID == template.id)
    }

    @Test func applyingEnglishTemplateUsesEnglishNameAndUnit() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = GoalCreationModel(store: context.store)
        model.apply(try template("water"), locale: english)
        #expect(model.name == "Drink water")
        #expect(model.unit == "glasses")
        #expect(model.canSave)
        model.apply(try template("gym"), locale: english)
        #expect(model.name == "Go to the gym")
        #expect(model.unit.isEmpty)
        #expect(model.period == .week && model.target == "3" && model.kind == .boolean)
        #expect(model.templateID == "gym")
        #expect(model.canSave)
    }

    @Test func matchingUsesTheSelectedLanguageAndIgnoresCaseAndAccents() throws {
        let water = try template("water")
        let read = try template("read")
        let gym = try template("gym")
        #expect(GoalCreationModel.matches(water, query: "su", locale: turkish))
        #expect(GoalCreationModel.matches(read, query: "KITAP", locale: turkish))
        #expect(GoalCreationModel.matches(gym, query: "spor", locale: turkish))
        #expect(GoalCreationModel.matches(try template("walk"), query: "yuru", locale: turkish))
        #expect(GoalCreationModel.matches(water, query: "DRINK", locale: english))
        #expect(GoalCreationModel.matches(read, query: "read", locale: english))
        #expect(!GoalCreationModel.matches(water, query: "su", locale: english))
        #expect(!GoalCreationModel.matches(read, query: "kitap", locale: english))
        for template in GoalTemplate.all {
            #expect(GoalCreationModel.matches(template, query: "", locale: turkish))
            #expect(!GoalCreationModel.matches(template, query: "xyz", locale: turkish))
        }
        #expect(
            GoalTemplate.all.filter { GoalCreationModel.matches($0, query: "su", locale: turkish) }.map(\.id) == [
                "water"
            ])
    }

    @Test func namesUnitsAndSummariesAreLocalized() throws {
        let water = try template("water")
        #expect(water.localizedName(locale: turkish) == "Su iç")
        #expect(water.localizedName(locale: english) == "Drink water")
        #expect(water.localizedUnit(locale: turkish) == "bardak")
        #expect(water.localizedUnit(locale: english) == "glasses")
        #expect(water.summary(locale: turkish) == "8 bardak / gün")
        #expect(water.summary(locale: english) == "8 glasses / day")
        #expect(try template("gym").summary(locale: turkish) == "Haftada 3")
        #expect(try template("gym").summary(locale: english) == "3 per week")
        #expect(try template("wake").summary(locale: turkish) == "Her gün")
        #expect(try template("wake").summary(locale: english) == "Every day")
    }

    @Test(arguments: GoalTemplate.all)
    func savingWritesAnOrdinaryDefinition(_ template: GoalTemplate) async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = GoalCreationModel(store: context.store)
        model.apply(template)
        #expect(await model.save())
        let goal = try #require((try await context.store.goalDefinitions()).first)
        let data = try Data(contentsOf: context.root.appendingPathComponent(goal.id))
        let document = RawDocument(bytes: data)
        guard case .parsed(let fields) = document.frontmatter else {
            Issue.record("Saved goal must have parsed frontmatter")
            return
        }
        func scalar(_ key: String) -> String? {
            guard case .scalar(let value) = fields.field(named: key)?.value else { return nil }
            return value.text
        }
        #expect(scalar("name") == model.name)
        #expect(scalar("kind") == template.kind.rawValue)
        #expect(scalar("period") == template.period.rawValue)
        #expect(scalar("target") == String(template.target))
        #expect(scalar("unit") == template.unit)
        #expect(scalar("icon") == nil)
        #expect(scalar("template") == nil)
        #expect(scalar("templateID") == nil)
        #expect(scalar("place") == nil)
        #expect(goal.kind == template.kind && goal.period == template.period)
        #expect(goal.target == Double(template.target) && goal.unit == template.unit)
    }

    @Test func customGoalStillSavesWithoutSelectingATemplate() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = GoalCreationModel(store: context.store)
        #expect(!model.canSave)
        model.name = "Özel hedef"
        #expect(model.templateID == nil)
        #expect(model.canSave)
        #expect(await model.save())
        let goal = try #require((try await context.store.goalDefinitions()).first)
        #expect(goal.name == "Özel hedef" && goal.kind == .boolean && goal.period == .day && goal.target == 1)
    }
}
