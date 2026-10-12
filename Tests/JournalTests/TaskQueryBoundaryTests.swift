import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// Where a task query cuts the vault (the list's first 50 completions, the timeline's year either
/// side of today) and when a day page's answer counts as current. Held to ``LegacyTaskViews``
/// over the published `tasks`.
@MainActor struct TaskQueryBoundaryTests {
    /// More than 50 completions, most on one day: the 50 the index picks are the 50 the list put
    /// first, through equal days, priorities and files whose names were decomposed on disk.
    @Test func theFirstFiftyCompletionsAreTheListsFirstFifty() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        // Ç, Ö and İ decomposed on disk; the index keeps paths composed.
        let names = ["C\u{327}alis\u{327}ma", "O\u{308}dev", "I\u{307}s\u{327}", "çay", "Zeta", "ilk", "Ana"]
        let priorities = ["", " ⏫", " 🔼", " 🔽", " 🔺"]
        var files: [String: String] = [:]
        for (number, name) in names.enumerated() {
            var lines: [String] = []
            for line in 0..<9 {
                let priority = priorities[(line + number) % priorities.count]
                let project = line % 3 == 0 ? " #project/Bahçe" : ""
                lines.append("- [x] \(name) \(line)\(priority)\(project) ✅ 2026-10-01")
            }
            lines.append("- [X] \(name) later ✅ 2026-10-02")
            lines.append("- [x] \(name) no day")
            lines.append("- [ ] \(name) open 📅 2026-10-01")
            files["notes/\(name).md"] = lines.joined(separator: "\n") + "\n"
        }
        try Self.write(files, in: context)
        await context.start()
        let all = try await context.store.allTasks()
        #expect(all.filter { $0.rawStatus.lowercased() == "x" }.count == names.count * 11)

        for project in [nil, "bahçe"] {
            let model = TasksModel(store: context.store, today: { context.today })
            model.projectFilter = project
            await model.loadList()
            let expected = LegacyTaskViews.completed(LegacyTaskViews.filtered(all, entity: nil, project: project))
            #expect(model.completed.count == min(50, expected.count))
            #expect(model.completed.queryKeys == expected.queryKeys, "\(project ?? "-")")
        }
    }

    /// The timeline asks for a year either side of today and its window moves only within that
    /// year, so a task beyond it was never drawn; one at the edge is, wherever the window goes.
    @Test func timelineWindowsMatchTheConstructionUpToTheYearsEdges() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let today = context.today
        func day(_ offset: Int) -> String { today.addingDays(offset)!.description }
        let source = [
            "- [ ] edge before 📅 \(day(-365)) ^edgebefore",
            "- [ ] beyond before 📅 \(day(-366)) ^beyondbefore",
            "- [ ] edge after 📅 \(day(365)) ^edgeafter",
            "- [ ] beyond after 🛫 \(day(366)) 📅 \(day(400)) ^beyondafter",
            "- [ ] long since 🛫 \(day(-500)) ^longsince",
            "- [ ] across 🛫 \(day(-400)) 📅 \(day(400)) ^across",
            "- [ ] reversed 🛫 \(day(370)) 📅 \(day(360)) ^reversed",
            "- [x] done far 📅 \(day(-365)) ✅ \(day(-1)) ^donefar",
            "- [-] cancelled edge 📅 \(day(365)) ^cancellededge",
            "- [ ] undated ^undated",
        ].joined(separator: "\n")
        try Self.write(["journal/\(today).md": source + "\n"], in: context)
        await context.start()
        let all = try await context.store.allTasks()
        let tasks = TasksModel(store: context.store, today: { today })
        let timeline = TimelineModel(tasks: tasks)
        timeline.grouping = .none
        await timeline.load()
        let bounds = timeline.bounds
        let length = 112
        let windows = [
            bounds.lowerBound...bounds.lowerBound.addingDays(length)!,
            bounds.upperBound.addingDays(-length)!...bounds.upperBound,
            bounds, today...today,
        ]
        for window in windows {
            timeline.setVisibleRange(window)
            let expected = LegacyTaskViews.timelineDated(all, today: today, window: timeline.visibleRange)
            #expect(timeline.groups.flatMap(\.rows).queryKeys == expected.queryKeys, "\(window)")
        }
        // Shifting past either end stops at the year's edge, as it always has.
        timeline.shiftWindow(by: 10_000)
        #expect(timeline.visibleRange.upperBound == bounds.upperBound)
        let far = Set(timeline.groups.flatMap(\.rows).compactMap(\.sourceIdentifier))
        #expect(far.isSuperset(of: ["edgeafter", "across", "reversed"]) && !far.contains("beyondafter"))
        timeline.shiftWindow(by: -10_000)
        #expect(timeline.visibleRange.lowerBound == bounds.lowerBound)
        let early = Set(timeline.groups.flatMap(\.rows).compactMap(\.sourceIdentifier))
        #expect(
            early.isSuperset(of: ["edgebefore", "across", "longsince", "donefar"]) && !early.contains("beyondbefore"))
        #expect(timeline.undated.compactMap(\.sourceIdentifier) == ["undated"])
    }

    /// A day page asked before the vault was published (no index yet: no rows) has an answer, but
    /// not the current one: the journal reminder must not open the flow on it.
    @Test func aDaysRowsFromBeforeThePublishAreNotCurrent() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let model = DayTasksModel(store: context.store, day: context.today, isToday: true)
        await model.load()
        #expect(model.isLoaded && model.rows?.isEmpty == true)

        await context.start()
        #expect(context.store.lastUpdated != nil)
        #expect(model.isLoaded && !model.isCurrent)
        await model.load()
        #expect(model.isCurrent && model.rows?.isEmpty == false)

        #expect(await context.store.addTask(on: context.today, text: "after", due: context.today))
        #expect(!model.isCurrent)
        await model.load()
        #expect(model.isCurrent && model.groups.dated.contains { $0.sourceText.hasPrefix("after") })
    }

    /// A weekly review load replaced by a newer one (a publish while it reads) shows no error.
    @Test func aReplacedWeeklyReviewLoadShowsNoError() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = WeeklyReviewModel(
            store: context.store, today: context.today, defaults: context.defaults.defaults)
        let gate = TaskQueryGate(store: context.store)
        gate.hold()
        let loading = Task { await model.load() }
        await gate.waitUntilHolding(1)
        loading.cancel()
        gate.release()
        await loading.value
        #expect(model.loadErrorText == nil)

        await model.load()
        #expect(model.loadErrorText == nil && model.content != nil)
    }

    private static func write(_ files: [String: String], in context: TaskTestContext) throws {
        for (path, text) in files {
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }
}
