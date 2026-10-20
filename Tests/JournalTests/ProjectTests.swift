import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

@MainActor struct ProjectTests {
    @Test func projectSummaryGroupsLinksAndActivity() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] [[Deniz Arıkan]] #project/Café 📅 2026-10-05 ^one
        - [/] [[Liman Ofis]] #project/café ^two
        - [x] Done #project/CAFÉ ✅ 2026-10-02 ^done
        - [-] Cancel #project/Café ^cancel
        - [ ] Child #project/Café/mobile ^child
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let tasks = TasksModel(store: context.store)
        await tasks.loadList()
        #expect(tasks.projects.filter { $0.lowercased() == "café" }.count == 1)
        var model = try await ProjectModel.loaded(store: context.store, name: "café")
        #expect(model.openCount == 2)
        #expect(model.openGroups.map(\.date) == [CalendarDate("2026-10-05"), nil])
        #expect(model.completed.count == 1)
        #expect(Set(model.entities.map(\.kind)) == ["person", "place"])
        #expect(model.lastActivity == context.today)
        #expect(try await ProjectModel.loaded(store: context.store, name: "missing").tasks.isEmpty)
        tasks.projectFilter = "café"
        await tasks.loadList()
        #expect(tasks.undated.count == 1)
        #expect(await tasks.toggle(try #require(model.openGroups.first?.rows.first)))
        model = try await ProjectModel.loaded(store: context.store, name: "café")
        #expect(model.openCount == 1)
        #expect(model.completed.count == 2)
    }

    @Test func projectSuggestionsRespectModeContextCursorAndUnicode() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addTask(on: context.today, text: "Plan #project/Café/mobile", due: nil))
        let entry = context.model()
        await entry.loadProjects()
        entry.text = "Plan #project/café"
        #expect(entry.projectSuggestions().isEmpty)
        entry.mode = .task
        #expect(entry.projectSuggestions() == ["Café/mobile"])
        entry.selectProjectSuggestion("Café/mobile")
        #expect(entry.text == "Plan #project/Café/mobile")
        entry.text = "Plan #project/ca tail"
        let cursor = "Plan #project/ca".utf8.count
        entry.selectProjectSuggestion("Café/mobile", at: cursor)
        #expect(entry.text == "Plan #project/Café/mobile tail")
        for invalid in ["`#project/ca", "[[#project/ca", "x#project/ca", "#project/ca ", "\\#project/ca"] {
            entry.text = invalid
            #expect(entry.projectSuggestions().isEmpty)
        }
        entry.text = "Plan #project/new"
        #expect(entry.projectSuggestions().isEmpty)
        #expect(await entry.submit(time: nil))
        #expect(try await context.store.computeProjects().contains("new"))
    }

    @Test func milestoneCardWritesTodayAndDoesNotRepeatAcrossDays() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let creation = GoalCreationModel(store: context.store)
        creation.name = "Portfolio"
        creation.kind = .milestone
        creation.target = ""
        #expect(await creation.save())
        let goal = try #require((try await context.store.goalDefinitions()).first)
        #expect(goal.period == .year)
        let model = GoalDayModel(store: context.store, day: context.today)
        await model.load()
        #expect(await model.toggle(goal))
        #expect(model.status(for: goal).completionDate == context.today)
        let next = GoalDayModel(store: context.store, day: context.today.addingDays(1)!)
        await next.load()
        #expect(await next.toggle(goal) == false)
        #expect(await model.toggle(goal))
        #expect(model.status(for: goal).completionDate == nil)
    }
}
