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

    private func presentation(_ context: TaskTestContext, isToday: Bool = true) async throws -> TodayPresentation {
        let store = context.store
        let tasks = await DayTasksModel.loaded(store: store, day: context.today, isToday: isToday)
        let rows = try await store.computeGoalStatuses(today: context.today)
        return TodayPresentation(
            day: try await store.computeDay(on: context.today), groups: tasks.groups, goals: rows.map(\.definition),
            goalStatuses: TodayPresentation.goalStatuses(rows),
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

        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        await model.goals.load()
        #expect(Set(model.tasks.map(\.sourceText)) == ["call", "no identifier", "carried", "from a note"])
        #expect(model.pendingGoals.map(\.key) == ["spor", "su"])
        #expect(model.tasks.allSatisfy { model.choice(for: $0) == .keep })
        #expect(!model.canApply)
        // Looking around, changing one's mind and pressing through every step is still "nothing".
        let row = try await context.row("call")
        model.choose(.done, for: row)
        #expect(model.canApply)
        model.choose(.keep, for: row)
        #expect(!model.canApply)
        await model.apply()
        #expect(model.report == nil)
        #expect(model.steps == [.tasks, .goals, .journal])
        #expect(model.stepNumber == 1 && model.stepCount == 3)
        model.advance()
        #expect(model.step == .goals && model.stepNumber == 2)
        model.advance()
        #expect(model.step == .journal && model.stepNumber == 3)
        model.advance()
        #expect(model.step == .journal)
        model.sentence = " \n\t"
        #expect(!model.canWriteSentence)
        await model.writeSentence()
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
        let model = try await CloseDayModel.opened(store: context.store, today: context.today, calendar: monday)
        model.choose(.done, for: try await context.row("done here"))
        model.choose(.tomorrow, for: try await context.row("to tomorrow"))
        model.choose(.nextWeek, for: try await context.row("to next week"))
        // Said out loud or left alone, "Kalsın" is the same thing.
        model.choose(.keep, for: try await context.row("stays"))
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
        let reopened = try await CloseDayModel.opened(store: context.store, today: context.today)
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
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.choose(.done, for: try await context.row("finish"))
        model.choose(.done, for: try await context.row("changed done"))
        model.choose(.tomorrow, for: try await context.row("move"))
        model.choose(.tomorrow, for: try await context.row("changed move"))
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
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.choose(.done, for: try await context.row("first"))
        let outside = "- [ ] newcomer 📅 2026-10-03\n- [ ] first 📅 2026-10-03\n- [ ] second 📅 2026-10-03\n"
        try await write(["journal/2026-10-03.md": outside], in: context)
        #expect(model.choice(for: try await context.row("newcomer")) == .keep)
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

        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
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
        let reopened = try await CloseDayModel.opened(store: context.store, today: context.today)
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
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.choose(.done, for: try await context.row("water"))
        model.choose(.done, for: try await context.row("under done"))
        model.choose(.tomorrow, for: try await context.row("under moved"))
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
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
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
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.choose(.done, for: try await context.row("closed outside"))
        model.choose(.done, for: try await context.row("removed outside"))
        model.choose(.nextWeek, for: try await context.row("moved then removed"))
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
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.choose(.done, for: try await context.row("once"))
        model.choose(.tomorrow, for: try await context.row("later"))
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

        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
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
        #expect(
            try await CloseDayModel.opened(store: context.store, today: context.today).pendingGoals.map(\.key) == [
                "spor", "su",
            ])
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

    /// An open task written today and due later is on Today (decision 82) but not in the flow:
    /// its due day is already chosen, and Yarına would pull it back.
    @Test func openTaskWrittenTodayAndDueLaterStaysOutOfTheFlow() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(
            ["journal/2026-10-03.md": "## Tasks\n- [ ] later 📅 2026-10-10 ^later\n- [ ] undated ^undated\n"],
            in: context)
        let today = await DayTasksModel.loaded(store: context.store, day: context.today, isToday: true)
        #expect(today.groups.created.map(\.sourceText) == ["later", "undated"])
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        #expect(model.tasks.map(\.sourceText) == ["undated"])
        #expect(model.steps.contains(.tasks))

        // Only the later one open: there is no task step.
        try await write(["journal/2026-10-03.md": "## Tasks\n- [ ] later 📅 2026-10-10 ^later\n"], in: context)
        let alone = try await CloseDayModel.opened(store: context.store, today: context.today)
        #expect(alone.tasks.isEmpty)
        #expect(!alone.steps.contains(.tasks))
    }

    @Test func entryRowShowsOnTodayWhileWorkIsOpenOrTheJournalIsEmpty() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        // Nothing written today: the row is there so a sentence can be added.
        #expect(try await offered(context))
        #expect(try await !offered(context, isToday: false))

        // A goal with a longer period is not the day's business, and there is still no journal.
        try await write(
            [
                "goals/Kitap.md":
                    "---\ntype: goal\nname: Kitap\nkey: kitap\nperiod: week\nkind: boolean\ntarget: 3\n---\n"
            ],
            in: context)
        #expect(try await offered(context))

        // A journal entry and nothing else open: the row goes away.
        try await write(["journal/2026-10-03.md": "## Journal\nA quiet day.\n"], in: context)
        #expect(try await !offered(context))
        #expect(try await !offered(context, isToday: false))

        // Only a task written today and due later is open: the flow would not list it, so the row
        // is not offered though Today counts it (decision 82). Due today, it is offered.
        try await write(
            ["journal/2026-10-03.md": "## Tasks\n- [ ] later 📅 2026-10-10 ^later\n\n## Journal\nA quiet day.\n"],
            in: context)
        #expect(try await presentation(context).remainingTaskCount == 1)
        #expect(try await !offered(context))
        try await write(
            ["journal/2026-10-03.md": "## Tasks\n- [ ] later 📅 2026-10-03 ^later\n\n## Journal\nA quiet day.\n"],
            in: context)
        #expect(try await offered(context))

        // One open task, even with a journal entry.
        try await write(
            ["journal/2026-10-03.md": "## Tasks\n- [ ] only 📅 2026-10-03 ^only\n\n## Journal\nA quiet day.\n"],
            in: context)
        #expect(try await offered(context))
        #expect(try await !offered(context, isToday: false))
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.choose(.done, for: try await context.row("only"))
        await model.apply()
        #expect(model.report?.completed == 1)
        #expect(try await !offered(context))

        // One unmarked daily goal, no open task, journal already written.
        try await write(["goals/Spor.md": try #require(Self.goalFiles["goals/Spor.md"])], in: context)
        #expect(try await offered(context))
        #expect(try await !offered(context, isToday: false))
        let goals = try await CloseDayModel.opened(store: context.store, today: context.today)
        await goals.goals.load()
        #expect(await goals.goals.toggle(try #require(goals.pendingGoals.first)))
        #expect(try await !offered(context))

        // Only the journal changes from here on: the task is done and the goal mark stays in the
        // same file. Headings alone (an Obsidian template) are not an entry: the row returns.
        let marked = try String(contentsOf: context.file, encoding: .utf8)
        #expect(marked.contains("A quiet day."))
        func journal(_ text: String) async throws {
            try await write(
                ["journal/2026-10-03.md": marked.replacingOccurrences(of: "A quiet day.", with: text)], in: context)
            let shown = try await presentation(context)
            #expect(shown.remainingTaskCount == 0 && shown.remainingGoalCount == 0)
        }
        try await journal("### Sabah\n### Akşam")
        #expect(try await offered(context))
        #expect(try await !offered(context, isToday: false))
        // A blank Journal is not one either.
        try await journal(" ")
        #expect(try await offered(context))
        // One sentence under a heading is.
        try await journal("### Akşam\nBir cümle.")
        #expect(try await !offered(context))
    }

    private func offered(_ context: TaskTestContext, isToday: Bool = true) async throws -> Bool {
        CloseDayEntry.isOffered(
            isToday: isToday, presentation: try await presentation(context, isToday: isToday),
            hasJournal: CloseDayEntry.hasJournal(try await context.store.computeDay(on: context.today)))
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

    /// Empty task and goal steps are not shown. The counter counts only the steps that remain.
    @Test func emptyStepsAreSkippedAndTheCounterFollows() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()

        let onlyJournal = try await CloseDayModel.opened(store: context.store, today: context.today, step: .tasks)
        #expect(onlyJournal.steps == [.journal] && onlyJournal.step == .journal)
        #expect(onlyJournal.stepNumber == 1 && onlyJournal.stepCount == 1)
        #expect(!onlyJournal.canGoBack && !onlyJournal.canAdvance)
        onlyJournal.advance()
        onlyJournal.back()
        #expect(onlyJournal.step == .journal)

        try await write(["journal/2026-10-03.md": "- [ ] only 📅 2026-10-03 ^only\n"], in: context)
        let tasks = try await CloseDayModel.opened(store: context.store, today: context.today)
        #expect(tasks.steps == [.tasks, .journal])
        #expect(tasks.step == .tasks && tasks.stepNumber == 1 && tasks.stepCount == 2)
        tasks.advance()
        #expect(tasks.step == .journal && tasks.stepNumber == 2)
        tasks.back()
        #expect(tasks.step == .tasks)

        try await write(
            [
                "journal/2026-10-03.md": "## Journal\nA quiet day.\n",
                "goals/Spor.md": try #require(Self.goalFiles["goals/Spor.md"]),
            ], in: context)
        let goals = try await CloseDayModel.opened(store: context.store, today: context.today, step: .tasks)
        #expect(goals.steps == [.goals, .journal] && goals.step == .goals)
        #expect(goals.stepNumber == 1 && goals.stepCount == 2 && !goals.canGoBack && goals.canAdvance)

        try await write(["journal/2026-10-03.md": "- [ ] only 📅 2026-10-03 ^only\n"], in: context)
        let opened = try await CloseDayModel.opened(store: context.store, today: context.today, step: .journal)
        #expect(opened.steps == [.tasks, .goals, .journal])
        #expect(opened.step == .journal && opened.stepNumber == 3 && opened.stepCount == 3)
        opened.back()
        #expect(opened.step == .goals && opened.stepNumber == 2)
        opened.back()
        #expect(opened.step == .tasks && opened.stepNumber == 1)
    }

    /// A journal reminder opens today's flow on the journal step. The day in the identifier is not
    /// the flow's day, so a reminder from yesterday does the same.
    @Test func journalReminderOpensTodaysCloseDayOnTheJournalStep() throws {
        let yesterday = try #require(NotificationDestination.from(identifier: "journal-2026-09-27"))
        let today = try #require(NotificationDestination.from(identifier: "journal-2026-10-03"))
        #expect(yesterday == .journal && today == .journal)
        let fromYesterday = NotificationNavigationRequest(destination: yesterday)
        let fromToday = NotificationNavigationRequest(destination: today)
        #expect(fromYesterday.closeDayRequestID == fromYesterday.id)
        #expect(fromToday.closeDayRequestID == fromToday.id)
        #expect(NotificationNavigationRequest(destination: .tasks).closeDayRequestID == nil)
        #expect(NotificationNavigationRequest(destination: .goals).closeDayRequestID == nil)
    }

    /// A tap stays the service's latest request until the next one, and Today can be built again
    /// for it (a Mac section switch): the flow opens once per tap, and only for the journal reminder.
    @Test func eachReminderTapOpensTheFlowOnce() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = NotificationService(center: center, defaults: defaults.defaults)
        service.activateAutomatically(environment: [:], arguments: [])
        await service.replanNow()

        center.response?(.journal)
        let tap = try #require(service.navigationRequest?.closeDayRequestID)
        #expect(CloseDayReminder.claim(tap))
        #expect(service.navigationRequest?.closeDayRequestID == tap)
        #expect(!CloseDayReminder.claim(service.navigationRequest?.closeDayRequestID))

        center.response?(.tasks)
        #expect(!CloseDayReminder.claim(service.navigationRequest?.closeDayRequestID))
        center.response?(.goals)
        #expect(!CloseDayReminder.claim(service.navigationRequest?.closeDayRequestID))

        center.response?(.journal)
        let next = try #require(service.navigationRequest?.closeDayRequestID)
        #expect(next != tap)
        #expect(CloseDayReminder.claim(next))
        #expect(!CloseDayReminder.claim(next))
    }

    @Test func aSentenceIsAppendedAndABlankOneTouchesNothing() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let before = try vaultFiles(context)
        let updated = context.store.lastUpdated
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.sentence = " \n\t"
        #expect(!model.canWriteSentence)
        #expect(model.canClose)
        await model.writeSentence()
        model.sentence = ""
        await model.writeSentence()
        #expect(try vaultFiles(context) == before)
        #expect(context.store.lastUpdated == updated)
        #expect(!FileManager.default.fileExists(atPath: context.file.path))

        model.sentence = "Sakin bir akşam."
        #expect(model.canWriteSentence && model.canClose)
        await model.writeSentence()
        #expect(model.sentence.isEmpty)
        #expect(model.journalNotice == String(localized: "Cümle günlüğe eklendi."))
        #expect(model.journalError == nil)
        #expect(model.canClose)
        let created = Data(
            "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Journal\n\nSakin bir akşam.\n".utf8)
        #expect(try read("journal/2026-10-03.md", in: context) == created)

        // A second sentence is another block under the first. The first bytes stay.
        model.sentence = "İkinci cümle."
        await model.writeSentence()
        let twice = try read("journal/2026-10-03.md", in: context)
        #expect(twice.starts(with: created))
        #expect(twice == Data((String(decoding: created, as: UTF8.self) + "\nİkinci cümle.\n").utf8))
    }

    @Test func anAppendKeepsThePrefixOnCRLFAndBOMAndDoesNotCreateATask() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let original = Data(
            "\u{FEFF}## Tasks\r\n- [ ] eski 📅 2026-10-03 ^eski\r\n\r\n## Journal\r\nEski satır\r\n".utf8)
        try await write(["journal/2026-10-03.md": String(decoding: original, as: UTF8.self)], in: context)
        // `write` encodes the string; the BOM and CRLF are in the string, so the bytes match.
        #expect(try read("journal/2026-10-03.md", in: context) == original)
        let tasksBefore = try await context.store.allTasks().count
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.sentence = "- [ ] süt al"
        await model.writeSentence()
        let after = try read("journal/2026-10-03.md", in: context)
        #expect(after.starts(with: original))
        #expect(after == original + Data("\r\n· - [ ] süt al\r\n".utf8))
        #expect(try await context.store.allTasks().count == tasksBefore)
        #expect(try await !context.store.allTasks().contains { $0.sourceText == "süt al" })

        model.sentence = "İlk satır\nİkinci satır"
        await model.writeSentence()
        let more = try read("journal/2026-10-03.md", in: context)
        #expect(more.starts(with: after))
        #expect(more == after + Data("\r\nİlk satır\r\nİkinci satır\r\n".utf8))
        #expect(try await context.store.allTasks().count == tasksBefore)
    }

    /// A file the writer cannot add to keeps every byte, and the message names the file, not the
    /// sentence the user typed: the sentence stays for another try.
    @Test(arguments: [
        "## Journal\n```\n",
        "## Journal\nEski\n~~~ swift\nlet a = 1\n",
    ])
    func aFileThatCannotTakeTheSentenceKeepsItsBytes(original: String) async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(["journal/2026-10-03.md": original], in: context)
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.sentence = "Yeni cümle"
        await model.writeSentence()
        #expect(
            model.journalError
                == String(
                    localized:
                        "Bugünün dosyasındaki günlük bölümüne eklenemiyor. Kapanmamış kod bloğunu ya da dosyanın başındaki alanları kontrol et."
                ))
        #expect(model.journalNotice == nil)
        #expect(model.sentence == "Yeni cümle" && model.canWriteSentence)
        #expect(try Data(contentsOf: context.file) == Data(original.utf8))
    }

    /// Whatever the file looks like, the write is one insertion: every byte that was there is
    /// still there, in order, around one new run that holds the sentence. The index reads the
    /// sentence as journal text, and no task or event is born.
    @Test(arguments: [
        "## Journal\nİlk\n\n## Notes\nNot\n",
        "## Journal\n",
        "",
        "## Events\n- 09:00 yürüyüş ^walk\n",
        "## Journal\nEski",
        "## Journal\r\nEski\r\n\r\n## Notes\r\nNot",
        "## Journal\rEski\r",
        "\u{FEFF}---\ntype: journal\ndate: 2026-10-03\n---\n## Journal\n### Sabah\n",
        // Never closed, so not frontmatter (as in Obsidian): the Journal below it takes the sentence.
        "---\ntype: journal\n## Journal\nEski\n",
    ])
    func aSentenceIsOneInsertionInAnyDayFile(original: String) async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(["journal/2026-10-03.md": original], in: context)
        let before = [UInt8](try Data(contentsOf: context.file))
        #expect(before == Array(original.utf8))
        let tasks = try await context.store.allTasks().count
        let events = try await context.store.computeDay(on: context.today).events.count
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.sentence = "Sakin bir akşam."
        await model.writeSentence()
        #expect(model.journalError == nil)
        let after = [UInt8](try Data(contentsOf: context.file))
        let prefix = zip(before, after).prefix { $0 == $1 }.count
        let suffix = min(
            zip(before.reversed(), after.reversed()).prefix { $0 == $1 }.count, before.count - prefix)
        #expect(prefix + suffix == before.count, "the old bytes are not all kept in order")
        let inserted = String(decoding: after[prefix..<(after.count - suffix)], as: UTF8.self)
        #expect(inserted.contains("Sakin bir akşam."))
        #expect(try await context.store.allTasks().count == tasks)
        #expect(try await context.store.computeDay(on: context.today).events.count == events)
        let journal = try await context.store.computeDay(on: context.today).journal
        #expect(journal.contains { $0.headingLevel == nil && $0.text.plainText == "Sakin bir akşam." })
    }

    /// A paste with a task, a section heading, a fence and an event line stays journal text: no
    /// task, event or section is born, and a later sentence still lands in the same Journal.
    @Test func aPastedStructureStaysJournalText() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let original = "## Tasks\n- [ ] eski ^eski\n\n## Events\n- 08:00 kahve ^kahve\n\n## Journal\nEski.\n"
        try await write(["journal/2026-10-03.md": original], in: context)
        let tasks = try await context.store.allTasks().count
        #expect(try await context.store.computeDay(on: context.today).events.count == 1)
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        model.sentence = "- [ ] süt al\n## Başlık\n```\n- 09:00 yürüyüş\n  - [ ] girintili"
        await model.writeSentence()
        #expect(model.journalError == nil)
        model.sentence = "Son cümle."
        await model.writeSentence()
        #expect(model.journalError == nil)
        let text = try String(contentsOf: context.file, encoding: .utf8)
        #expect(text.hasPrefix(original))
        #expect(try await context.store.allTasks().count == tasks)
        let day = try await context.store.computeDay(on: context.today)
        #expect(day.events.count == 1)
        #expect(day.journal.last?.text.plainText == "Son cümle.")
    }

    /// While a write is in flight the sheet cannot close and a second "Yaz" writes nothing.
    @Test func aWriteInFlightHoldsTheSheetAndASecondTapWritesNothing() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(["journal/2026-10-03.md": "## Journal\nEski\n"], in: context)
        let store = context.store
        let gate = FirstWriteGate()
        let calls = CallCount()
        let model = try await CloseDayModel.opened(
            store: store, today: context.today,
            append: { day, lines in
                calls.value += 1
                await gate.holdIfFirst()
                try await store.appendToJournal(on: day, lines: lines)
            })
        model.sentence = "Bir kez"
        let first = Task { await model.writeSentence() }
        await gate.waitUntilFirst()
        #expect(!model.canClose && !model.canWriteSentence)
        await model.writeSentence()
        #expect(calls.value == 1)
        await gate.open()
        await first.value
        #expect(calls.value == 1 && model.canClose && model.sentence.isEmpty)
        #expect(try String(contentsOf: context.file, encoding: .utf8) == "## Journal\nEski\n\nBir kez\n")
    }

    /// The bytes are in the file when only the index failed: the sentence is not offered again.
    @Test func anIndexFailureAfterTheWriteIsNotRepeated() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(["journal/2026-10-03.md": "## Journal\nEski\n"], in: context)
        let store = context.store
        let calls = CallCount()
        let model = try await CloseDayModel.opened(
            store: store, today: context.today,
            append: { day, lines in
                calls.value += 1
                try await store.appendToJournal(on: day, lines: lines)
                throw VaultStoreError.indexUpdateFailed(
                    path: "journal/\(day).md", underlying: CocoaError(.fileWriteUnknown))
            })
        model.sentence = "Bir kez"
        await model.writeSentence()
        #expect(model.journalError == String(localized: "Değişiklik kaydedildi, indeks güncellenemedi."))
        #expect(model.journalNotice == nil)
        #expect(model.sentence.isEmpty && !model.canWriteSentence && model.canClose)
        await model.writeSentence()
        #expect(calls.value == 1)
        #expect(try String(contentsOf: context.file, encoding: .utf8) == "## Journal\nEski\n\nBir kez\n")
    }

    /// A refusal before any byte is written keeps the sentence; the next "Yaz" writes it once.
    @Test func aStaleTargetKeepsTheSentenceForARetry() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(["journal/2026-10-03.md": "## Journal\nEski\n"], in: context)
        let store = context.store
        let calls = CallCount()
        let model = try await CloseDayModel.opened(
            store: store, today: context.today,
            append: { day, lines in
                calls.value += 1
                if calls.value == 1 { throw VaultStoreError.staleTarget }
                try await store.appendToJournal(on: day, lines: lines)
            })
        model.sentence = "Bir kez"
        await model.writeSentence()
        #expect(model.journalError == DayEditError.message(for: VaultStoreError.staleTarget))
        #expect(model.sentence == "Bir kez" && model.canWriteSentence)
        #expect(try String(contentsOf: context.file, encoding: .utf8) == "## Journal\nEski\n")
        await model.writeSentence()
        #expect(calls.value == 2 && model.journalError == nil && model.journalNotice != nil)
        #expect(try String(contentsOf: context.file, encoding: .utf8) == "## Journal\nEski\n\nBir kez\n")
    }

    /// A sentence typed for one vault is not written into a vault selected since the flow opened.
    @Test func anotherVaultSelectedSinceOpeningIsNotWritten() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await write(["journal/2026-10-03.md": "## Journal\nEski\n"], in: context)
        let model = try await CloseDayModel.opened(store: context.store, today: context.today)
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.copyItem(at: context.root, to: other)
        let first = try vaultFiles(context)
        await context.store.select(other)
        #expect(context.store.vaultURL?.standardizedFileURL.path != context.root.standardizedFileURL.path)
        #expect(context.store.canAddEvent)
        let otherFile = other.appendingPathComponent("journal/2026-10-03.md")
        let otherBytes = try Data(contentsOf: otherFile)
        model.sentence = "Yanlış kasa"
        #expect(!model.canWriteSentence)
        await model.writeSentence()
        #expect(try Data(contentsOf: otherFile) == otherBytes)
        #expect(try vaultFiles(context) == first)
    }
}

/// Lets the first write in and holds it there until the test opens the gate; later writes pass.
private actor FirstWriteGate {
    private var entered = false
    private var isOpen = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func holdIfFirst() async {
        guard !entered else { return }
        entered = true
        arrival?.resume()
        arrival = nil
        guard !isOpen else { return }
        await withCheckedContinuation { release = $0 }
    }

    func waitUntilFirst() async {
        guard !entered else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func open() {
        isOpen = true
        release?.resume()
        release = nil
    }
}

@MainActor
private final class CallCount {
    var value = 0
}

private struct VaultFile: Equatable {
    let bytes: Data
    let modified: Date?
}
