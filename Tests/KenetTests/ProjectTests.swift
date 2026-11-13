import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Kenet

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
        await context.store.refreshAndSettle()
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

    /// The project page's "Açık görevler" groups: carried over, this week, later, undated.
    @Test func openSectionsSplitAroundTodayAndTheWeek() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try FileManager.default.createDirectory(
            at: context.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 2026-10-03 is a Saturday.
        try """
        ## Tasks
        - [ ] Later #project/depo 📅 2026-10-05 ^later
        - [ ] Sunday #project/depo 📅 2026-10-04 ^sunday
        - [ ] Undated #project/depo ^undated
        - [ ] Today #project/depo 📅 2026-10-03 ^today
        - [ ] Old #project/depo 📅 2026-10-01 ^old
        - [ ] Older #project/depo 📅 2026-09-20 ^older
        - [x] Done #project/depo 📅 2026-10-01 ✅ 2026-10-02 ^done
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refreshAndSettle()
        let model = try await ProjectModel.loaded(store: context.store, name: "depo")
        func blocks(_ sections: [ProjectOpenSection]) -> [[String]] {
            sections.map { section in section.rows.map { $0.sourceIdentifier ?? "" } }
        }

        var monday = Calendar(identifier: .gregorian)
        monday.firstWeekday = 2
        let mondayFirst = model.openSections(asOf: context.today, calendar: monday)
        #expect(mondayFirst.map(\.kind) == [.carriedOver, .thisWeek, .later, .undated])
        #expect(blocks(mondayFirst) == [["older", "old"], ["today", "sunday"], ["later"], ["undated"]])
        #expect(mondayFirst.map(\.rows.count).reduce(0, +) == model.openCount)

        // A Sunday-first week ends on that Saturday: Sunday's task is no longer this week's.
        var sunday = Calendar(identifier: .gregorian)
        sunday.firstWeekday = 1
        let sundayFirst = model.openSections(asOf: context.today, calendar: sunday)
        #expect(blocks(sundayFirst) == [["older", "old"], ["today"], ["sunday", "later"], ["undated"]])

        // An empty group is left out.
        let afterAll = model.openSections(asOf: try #require(CalendarDate("2026-11-01")), calendar: monday)
        #expect(afterAll.map(\.kind) == [.carriedOver, .undated])
        #expect(ProjectOpenSection.Kind.carriedOver.catalogKey == "Devreden")
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
