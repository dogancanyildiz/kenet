import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// The flow against real vault files: what it writes is compared byte for byte.
@MainActor
struct CloseDayTests {
    private static let goalFiles = [
        "goals/Spor.md": "---\ntype: goal\nname: Spor\nkey: spor\nperiod: day\nkind: boolean\ntarget: 1\n---\n",
        "goals/Su.md": "---\ntype: goal\nname: Su\nkey: su\nperiod: day\nkind: number\ntarget: 8\nunit: bardak\n---\n",
        "goals/Kitap.md":
            "---\ntype: goal\nname: Kitap\nkey: kitap\nperiod: day\nkind: number\ntarget: 20\nunit: sayfa\n---\n",
    ]
    private static let todayWithGoals =
        "---\ntype: journal\ndate: 2026-10-03\ngoals:\n  kitap: 20\n  su: 3\n---\n\n## Tasks\n"
        + "- [ ] call 📅 2026-10-03 ⏫ ^call\n- [ ] no identifier\n\n## Events\n- 09:00 walk ^walk\n\n"
        + "## Journal\nA quiet day.\n"

    private func write(_ files: [String: String], in context: TaskTestContext) async throws {
        for (path, text) in files {
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        await context.store.refresh()
    }

    /// Every file under the vault root: bytes and modification date.
    private func vaultFiles(_ context: TaskTestContext) throws -> [String: VaultFile] {
        let root = context.root.resolvingSymlinksInPath()
        var result: [String: VaultFile] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let found = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys))
        for case let url as URL in found {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
            result[path] = VaultFile(bytes: try Data(contentsOf: url), modified: values.contentModificationDate)
        }
        return result
    }

    private func read(_ path: String, in context: TaskTestContext) throws -> Data {
        try Data(contentsOf: context.root.appendingPathComponent(path))
    }

    private func presentation(_ context: TaskTestContext, isToday: Bool = true) -> TodayPresentation {
        let store = context.store
        let tasks = DayTasksModel(store: store, day: context.today, isToday: isToday)
        return TodayPresentation(
            day: store.content.day(on: context.today), groups: tasks.groups, goals: store.content.goals,
            goalStatuses: TodayPresentation.goalStatuses(
                goals: store.content.goals, logs: store.content.goalLogs, day: context.today),
            goalStatusesDay: context.today, today: context.today, locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian))
    }

    private func numbers(_ text: String?) -> [String] {
        (text ?? "").split(whereSeparator: { !$0.isNumber }).map(String.init)
    }

    @Test func closingWithoutAChoiceLeavesEveryFileUntouched() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        var files = Self.goalFiles
        files["journal/2026-10-03.md"] = Self.todayWithGoals
        files["journal/2026-10-01.md"] =
            "\u{FEFF}## Tasks\r\n- [ ] carried 📅 2026-10-01 ^carried\r\n  kept note\r\n\r\n## Journal\r\nno final newline"
        files["notes/Plan.md"] = "# Plan\n- [ ] from a note 📅 2026-10-03\n"
        try await write(files, in: context)
        let before = try vaultFiles(context)
        // The store's own files (vault settings, templates) are part of "every file" too.
        #expect(Set(files.keys).isSubset(of: Set(before.keys)) && before.count > files.count)

        let model = CloseDayModel(store: context.store, today: context.today)
        await model.goals.load()
        #expect(Set(model.tasks.map(\.sourceText)) == ["call", "no identifier", "carried", "from a note"])
        #expect(model.pendingGoals.map(\.key) == ["spor", "su"])
        #expect(model.tasks.allSatisfy { model.choice(for: $0) == .keep })
        #expect(!model.canApply)
        // Looking around, changing one's mind and pressing through every step is still "nothing".
        let row = try context.row("call")
        model.choose(.done, for: row)
        #expect(model.canApply)
        model.choose(.keep, for: row)
        #expect(!model.canApply)
        await model.apply()
        #expect(model.report == nil)
        model.advance()
        #expect(model.step == .goals)
        model.advance()
        #expect(model.step == .goals)
        model.back()
        model.back()
        #expect(model.step == .tasks)
        await model.apply()

        #expect(try vaultFiles(context) == before)
    }

    @Test func mixedChoicesRewriteOnlyTheChosenLines() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let today =
            "## Tasks\n- [ ] done here 📅 2026-10-03 ^done\n- [ ] to tomorrow 📅 2026-10-03 ⏫ ^tom\n"
            + "- [ ] stays 📅 2026-10-03 ^stay\n- [ ] undated stays ^undated\n\n## Journal\nUnrelated text.\n"
        let older =
            "## Tasks\r\n- [ ] to next week 📅 2026-10-01 ^week\r\n- [ ] old stays 📅 2026-09-30 ^old\r\n"
            + "  note under\r\n"
        let note = "- [ ] note stays 📅 2026-10-02 ^note\n"
        try await write(
            ["journal/2026-10-03.md": today, "journal/2026-10-01.md": older, "notes/Plan.md": note], in: context)
        let before = try vaultFiles(context)

        // "Haftaya" follows the calendar's week start; the expected date below is a Monday week's.
        var monday = Calendar(identifier: .gregorian)
        monday.firstWeekday = 2
        let model = CloseDayModel(store: context.store, today: context.today, calendar: monday)
        model.choose(.done, for: try context.row("done here"))
        model.choose(.tomorrow, for: try context.row("to tomorrow"))
        model.choose(.nextWeek, for: try context.row("to next week"))
        // Said out loud or left alone, "Kalsın" is the same thing.
        model.choose(.keep, for: try context.row("stays"))
        #expect(model.canApply)
        await model.apply()

        let report = try #require(model.report)
        #expect(report.completed == 1 && report.moves == TaskMoveReport(moved: 2))
        #expect(report.completionUnchanged == 0 && report.completionFailed == 0 && report.failureText == nil)
        #expect(!report.isPartial)
        #expect(numbers(report.text(locale: Locale(identifier: "en_US"))) == ["1", "2"])
        let expectedToday =
            "## Tasks\n- [x] done here 📅 2026-10-03 ✅ 2026-10-03 ^done\n"
            + "- [ ] to tomorrow 📅 2026-10-04 ⏫ ^tom\n"
            + "- [ ] stays 📅 2026-10-03 ^stay\n- [ ] undated stays ^undated\n\n## Journal\nUnrelated text.\n"
        let expectedOlder =
            "## Tasks\r\n- [ ] to next week 📅 2026-10-05 ^week\r\n- [ ] old stays 📅 2026-09-30 ^old\r\n"
            + "  note under\r\n"
        #expect(try read("journal/2026-10-03.md", in: context) == Data(expectedToday.utf8))
        #expect(try read("journal/2026-10-01.md", in: context) == Data(expectedOlder.utf8))
        let after = try vaultFiles(context)
        #expect(after["notes/Plan.md"] == before["notes/Plan.md"])
        #expect(after.count == before.count)

        // The list follows the vault: handled tasks are gone, here and when the flow opens again.
        let left: Set<String> = ["stays", "undated stays", "old stays", "note stays"]
        #expect(Set(model.tasks.map(\.sourceText)) == left)
        #expect(!model.canApply)
        let reopened = CloseDayModel(store: context.store, today: context.today)
        #expect(Set(reopened.tasks.map(\.sourceText)) == left)
        #expect(reopened.report == nil)
    }

    @Test func aTaskChangedOutsideIsCountedAndTheRestStillWrite() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "- [ ] finish 📅 2026-10-03 ^a\n- [ ] changed done 📅 2026-10-03 ^b\n"
            + "- [ ] move 📅 2026-10-03 ^c\n- [ ] changed move 📅 2026-10-03 ^d\n"
        try await write(["journal/2026-10-03.md": source], in: context)
        let model = CloseDayModel(store: context.store, today: context.today)
        model.choose(.done, for: try context.row("finish"))
        model.choose(.done, for: try context.row("changed done"))
        model.choose(.tomorrow, for: try context.row("move"))
        model.choose(.tomorrow, for: try context.row("changed move"))
        // Outside the app, after the list was drawn.
        let outside = source.replacingOccurrences(of: "] changed ", with: "] edited ")
        try Data(outside.utf8).write(to: context.file)
        await model.apply()

        let report = try #require(model.report)
        #expect(report.completed == 1 && report.completionUnchanged == 1 && report.completionFailed == 0)
        #expect(report.moves == TaskMoveReport(moved: 1, unchanged: 1))
        #expect(report.isPartial)
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "tr_TR")] {
            #expect(numbers(report.text(locale: locale)) == ["1", "1", "1", "1"])
        }
        let expected =
            "- [x] finish 📅 2026-10-03 ✅ 2026-10-03 ^a\n- [ ] edited done 📅 2026-10-03 ^b\n"
            + "- [ ] move 📅 2026-10-04 ^c\n- [ ] edited move 📅 2026-10-03 ^d\n"
        #expect(try Data(contentsOf: context.file) == Data(expected.utf8))
        #expect(Set(model.tasks.map(\.sourceText)) == ["edited done", "edited move"])
        #expect(model.tasks.allSatisfy { model.choice(for: $0) == .keep })
    }

    /// A task without a block identifier is named by its line. When an outside edit puts another
    /// task on that line, the choice made for the old one must not reach it.
    @Test func aChoiceDoesNotSlideOntoAnotherTask() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(["journal/2026-10-03.md": "- [ ] first 📅 2026-10-03\n- [ ] second 📅 2026-10-03\n"], in: context)
        let model = CloseDayModel(store: context.store, today: context.today)
        model.choose(.done, for: try context.row("first"))
        let outside = "- [ ] newcomer 📅 2026-10-03\n- [ ] first 📅 2026-10-03\n- [ ] second 📅 2026-10-03\n"
        try await write(["journal/2026-10-03.md": outside], in: context)
        #expect(model.choice(for: try context.row("newcomer")) == .keep)
        await model.apply()
        #expect(try Data(contentsOf: context.file) == Data(outside.utf8))
    }

    @Test func goalsAreMarkedThroughTheDayModelAndLeaveTheListOnTheNextOpening() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        var files = Self.goalFiles
        files["journal/2026-10-03.md"] = Self.todayWithGoals
        files["journal/2026-10-02.md"] = "---\ntype: journal\ndate: 2026-10-02\ngoals:\n  spor: true\n---\n"
        try await write(files, in: context)
        let before = try vaultFiles(context)

        let model = CloseDayModel(store: context.store, today: context.today)
        await model.goals.load()
        // Kitap is at its target today; yesterday's Spor mark does not count for today.
        #expect(model.pendingGoals.map(\.key) == ["spor", "su"])
        let spor = try #require(model.pendingGoals.first { $0.key == "spor" })
        #expect(await model.goals.toggle(spor))

        let marked = Self.todayWithGoals.replacingOccurrences(of: "  su: 3\n", with: "  su: 3\n  spor: true\n")
        #expect(try Data(contentsOf: context.file) == Data(marked.utf8))
        var after = try vaultFiles(context)
        after["journal/2026-10-03.md"] = before["journal/2026-10-03.md"]
        #expect(after == before)
        // Still listed (and reversible) in this opening; gone from the next one.
        #expect(model.pendingGoals.map(\.key) == ["spor", "su"])
        #expect(model.goals.isComplete(for: spor))
        let reopened = CloseDayModel(store: context.store, today: context.today)
        #expect(reopened.pendingGoals.map(\.key) == ["su"])
    }

    /// Completing a recurring task writes its next instance above it and shifts every line below.
    /// The tasks chosen under it are still found, and the new instance is listed as open.
    @Test func aRecurringTaskIsCompletedOnceAndTheRowsUnderItStillWrite() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "- [ ] water 🔁 every day 📅 2026-10-01 ^water\n- [ ] under done 📅 2026-10-03\n"
            + "- [ ] under moved 📅 2026-10-03\n- [ ] under kept 📅 2026-10-03\n"
        try await write(["journal/2026-10-03.md": source], in: context)
        let model = CloseDayModel(store: context.store, today: context.today)
        model.choose(.done, for: try context.row("water"))
        model.choose(.done, for: try context.row("under done"))
        model.choose(.tomorrow, for: try context.row("under moved"))
        await model.apply()

        let report = try #require(model.report)
        #expect(report.completed == 2 && report.moves == TaskMoveReport(moved: 1) && !report.isPartial)
        let lines = String(decoding: try Data(contentsOf: context.file), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        try #require(lines.count == 5)
        // The next instance: one day after the old due date, with an identifier of its own.
        #expect(lines.first?.hasPrefix("- [ ] water 🔁 every day 📅 2026-10-02 ^") == true)
        // A written task without an identifier is given one (vault format); the rest is as chosen.
        #expect(lines[1] == "- [x] water 🔁 every day 📅 2026-10-01 ✅ 2026-10-03 ^water")
        #expect(lines[2].hasPrefix("- [x] under done 📅 2026-10-03 ✅ 2026-10-03 ^"))
        #expect(lines[3].hasPrefix("- [ ] under moved 📅 2026-10-04 ^"))
        #expect(lines[4] == "- [ ] under kept 📅 2026-10-03")
        // Still behind today, so it is open business like on Today; nothing is chosen for it.
        #expect(model.tasks.map(\.sourceText) == ["water", "under kept"])
        #expect(model.tasks.allSatisfy { model.choice(for: $0) == .keep })
    }

    /// Two tasks that read the same are still two rows: the choice reaches the one it was made on.
    @Test func aChoiceOnOneOfTwoIdenticalTasksWritesThatLine() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "- [ ] twin 📅 2026-10-03\n- [ ] other 📅 2026-10-03\n- [ ] twin 📅 2026-10-03\n"
        try await write(["journal/2026-10-03.md": source], in: context)
        let model = CloseDayModel(store: context.store, today: context.today)
        let twins = model.tasks.filter { $0.sourceText == "twin" }.sorted { $0.sourceLine < $1.sourceLine }
        #expect(twins.count == 2)
        model.choose(.done, for: twins[1])
        #expect(model.choice(for: twins[0]) == .keep)
        await model.apply()

        #expect(model.report?.completed == 1)
        // The written line also gets its identifier (vault format); the first twin keeps its bytes.
        let written = String(decoding: try Data(contentsOf: context.file), as: UTF8.self)
        let kept = "- [ ] twin 📅 2026-10-03\n- [ ] other 📅 2026-10-03\n"
        #expect(written.hasPrefix(kept + "- [x] twin 📅 2026-10-03 ✅ 2026-10-03 ^"))
        #expect(written.split(separator: "\n").count == 3)
    }

    /// Tasks that were closed or removed outside while the flow was open: nothing is written for
    /// them, each is counted, and the file keeps the outside bytes.
    @Test func tasksClosedOrRemovedOutsideAreCountedAndNotWritten() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "- [ ] closed outside 📅 2026-10-03 ^a\n- [ ] removed outside 📅 2026-10-03 ^b\n"
            + "- [ ] moved then removed 📅 2026-10-03 ^c\n- [ ] untouched 📅 2026-10-03 ^d\n"
        try await write(["journal/2026-10-03.md": source], in: context)
        let model = CloseDayModel(store: context.store, today: context.today)
        model.choose(.done, for: try context.row("closed outside"))
        model.choose(.done, for: try context.row("removed outside"))
        model.choose(.nextWeek, for: try context.row("moved then removed"))
        let outside = "- [x] closed outside 📅 2026-10-03 ✅ 2026-10-02 ^a\n- [ ] untouched 📅 2026-10-03 ^d\n"
        try Data(outside.utf8).write(to: context.file)
        await model.apply()

        let report = try #require(model.report)
        #expect(report.completed == 0 && report.completionUnchanged == 2 && report.completionFailed == 0)
        #expect(report.moves == TaskMoveReport(unchanged: 1))
        #expect(report.isPartial)
        #expect(try Data(contentsOf: context.file) == Data(outside.utf8))
        #expect(model.tasks.map(\.sourceText) == ["untouched"])
    }

    /// A second "Uygula" while the first is writing does nothing: no second write, and the first
    /// report is not replaced by one that counts the same tasks as changed.
    @Test func applyingTwiceAtOnceWritesOnce() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(
            ["journal/2026-10-03.md": "- [ ] once 📅 2026-10-03 ^once\n- [ ] later 📅 2026-10-03 ^later\n"],
            in: context)
        let model = CloseDayModel(store: context.store, today: context.today)
        model.choose(.done, for: try context.row("once"))
        model.choose(.tomorrow, for: try context.row("later"))
        #expect(model.canClose)
        async let first: Void = model.apply()
        async let second: Void = model.apply()
        _ = await (first, second)

        #expect(model.report == CloseDayReport(completed: 1, moves: TaskMoveReport(moved: 1)))
        #expect(model.canClose && !model.isApplying)
        let expected = "- [x] once 📅 2026-10-03 ✅ 2026-10-03 ^once\n- [ ] later 📅 2026-10-04 ^later\n"
        #expect(try Data(contentsOf: context.file) == Data(expected.utf8))
    }

    /// A mark made in the flow is the Today strip's mark, and taking it back restores the bytes.
    @Test func aGoalMarkedAndUnmarkedLeavesTheFileAsItWas() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        var files = Self.goalFiles
        files["journal/2026-10-03.md"] = Self.todayWithGoals
        files["goals/Hafta.md"] =
            "---\ntype: goal\nname: Hafta\nkey: hafta\nperiod: week\nkind: boolean\ntarget: 3\n---\n"
        files["goals/Yil.md"] =
            "---\ntype: goal\nname: Yil\nkey: yil\nperiod: year\nkind: number\ntarget: 50\n---\n"
        try await write(files, in: context)
        let before = try vaultFiles(context)

        let model = CloseDayModel(store: context.store, today: context.today)
        await model.goals.load()
        // Weekly and yearly goals are not the day's business, however far from their targets.
        #expect(model.pendingGoals.map(\.key) == ["spor", "su"])
        let spor = try #require(model.pendingGoals.first { $0.key == "spor" })
        let water = try #require(model.pendingGoals.first { $0.key == "su" })

        // The same call the Today strip makes for "+" on a number goal: one more than today's value.
        #expect(model.goals.value(for: water) == .number(3))
        #expect(await model.goals.set(water, value: .number(4)))
        let more = Self.todayWithGoals.replacingOccurrences(of: "  su: 3\n", with: "  su: 4\n")
        #expect(try Data(contentsOf: context.file) == Data(more.utf8))
        // Short of the target of 8: still open, also for the next opening.
        #expect(!model.goals.isComplete(for: water))
        #expect(CloseDayModel(store: context.store, today: context.today).pendingGoals.map(\.key) == ["spor", "su"])
        #expect(await model.goals.set(water, value: .number(3)))
        #expect(try Data(contentsOf: context.file) == Data(Self.todayWithGoals.utf8))

        #expect(await model.goals.toggle(spor))
        #expect(model.goals.isComplete(for: spor))
        #expect(try Data(contentsOf: context.file) != Data(Self.todayWithGoals.utf8))
        #expect(await model.goals.toggle(spor))
        #expect(!model.goals.isComplete(for: spor))
        #expect(try Data(contentsOf: context.file) == Data(Self.todayWithGoals.utf8))
        var after = try vaultFiles(context)
        after["journal/2026-10-03.md"] = before["journal/2026-10-03.md"]
        #expect(after == before)
    }

    @Test func entryRowShowsOnlyOnTodayWhileSomethingIsOpen() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        // Nothing at all.
        #expect(!CloseDayEntry.isOffered(isToday: true, presentation: presentation(context)))

        // A goal with a longer period is not the day's business.
        try await write(
            [
                "goals/Kitap.md":
                    "---\ntype: goal\nname: Kitap\nkey: kitap\nperiod: week\nkind: boolean\ntarget: 3\n---\n"
            ],
            in: context)
        #expect(!CloseDayEntry.isOffered(isToday: true, presentation: presentation(context)))

        // One open task.
        try await write(["journal/2026-10-03.md": "- [ ] only 📅 2026-10-03 ^only\n"], in: context)
        #expect(CloseDayEntry.isOffered(isToday: true, presentation: presentation(context)))
        #expect(!CloseDayEntry.isOffered(isToday: false, presentation: presentation(context, isToday: false)))
        let model = CloseDayModel(store: context.store, today: context.today)
        model.choose(.done, for: try context.row("only"))
        await model.apply()
        #expect(model.report?.completed == 1)
        #expect(!CloseDayEntry.isOffered(isToday: true, presentation: presentation(context)))

        // One unmarked daily goal, no open task.
        try await write(["goals/Spor.md": try #require(Self.goalFiles["goals/Spor.md"])], in: context)
        #expect(CloseDayEntry.isOffered(isToday: true, presentation: presentation(context)))
        #expect(!CloseDayEntry.isOffered(isToday: false, presentation: presentation(context, isToday: false)))
        let goals = CloseDayModel(store: context.store, today: context.today)
        await goals.goals.load()
        #expect(await goals.goals.toggle(try #require(goals.pendingGoals.first)))
        #expect(!CloseDayEntry.isOffered(isToday: true, presentation: presentation(context)))
    }

    @Test func reportNamesEveryOutcomeAndIsSilentWhenNothingHappened() {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "tr_TR")] {
            #expect(CloseDayReport().text(locale: locale) == nil)
            let all = CloseDayReport(
                completed: 2, completionUnchanged: 3, completionFailed: 4,
                moves: TaskMoveReport(moved: 5, unchanged: 6, failed: 7))
            #expect(numbers(all.text(locale: locale)) == ["2", "3", "4", "5", "6", "7"])
            // Completing and moving are told apart, and so are their two ways of not happening.
            let sentences = Set(
                [
                    CloseDayReport(completed: 2), CloseDayReport(completionUnchanged: 2),
                    CloseDayReport(completionFailed: 2), CloseDayReport(moves: TaskMoveReport(moved: 2)),
                    CloseDayReport(moves: TaskMoveReport(unchanged: 2)),
                ].compactMap { $0.text(locale: locale) })
            #expect(sentences.count == 5)
        }
        #expect(!CloseDayReport(completed: 1, moves: TaskMoveReport(moved: 1)).isPartial)
        #expect(CloseDayReport(completionUnchanged: 1).isPartial)
        #expect(CloseDayReport(completionFailed: 1).isPartial)
        #expect(CloseDayReport(moves: TaskMoveReport(failed: 1)).isPartial)
    }
}

private struct VaultFile: Equatable {
    let bytes: Data
    let modified: Date?
}
