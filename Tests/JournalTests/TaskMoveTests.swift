import DateParsing
import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

@MainActor
struct TaskMoveDateTests {
    /// Quick entry is driven through its own model, so the menu is compared with what the box really writes.
    @Test func nextWeekIsTheDayQuickEntryGivesOnEveryWeekdayAndAcrossTheYearEnd() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let first = CalendarDate("2026-12-21")!
        var weekdays: Set<Int> = []
        for offset in 0..<21 {
            let today = try #require(first.addingDays(offset))
            weekdays.insert(today.weekday)
            let menu = TaskMove.date(.nextWeek, today: today)
            #expect(menu != nil)
            #expect(menu == typed("call haftaya", today, [.turkish], in: context), "\(today)")
            #expect(menu == typed("call next week", today, [.english], in: context), "\(today)")
            #expect(
                TaskMove.date(.tomorrow, today: today) == typed("call yarın", today, [.turkish], in: context),
                "\(today)")
            #expect(TaskMove.date(.today, today: today) == today)
        }
        #expect(weekdays.count == 7)
    }

    @Test func nextWeekIsTheStartOfTheFollowingWeek() {
        let saturday = CalendarDate("2026-10-03")!
        let sunday = CalendarDate("2026-10-04")!
        let monday = CalendarDate("2026-10-05")!
        let yearEnd = CalendarDate("2026-12-31")!
        #expect(monday.weekday == 0)
        let week = WeekStartTests.calendar(firstWeekday: 2)
        #expect(TaskMove.date(.nextWeek, today: saturday, calendar: week) == monday)
        #expect(TaskMove.date(.nextWeek, today: sunday, calendar: week) == monday)
        // On the first day of the week the move is a full week, never the same day.
        #expect(TaskMove.date(.nextWeek, today: monday, calendar: week) == CalendarDate("2026-10-12"))
        #expect(TaskMove.date(.nextWeek, today: yearEnd, calendar: week) == CalendarDate("2027-01-04"))
        #expect(TaskMove.date(.tomorrow, today: yearEnd, calendar: week) == CalendarDate("2027-01-01"))
    }

    @Test func optionsSkipTheDayTheTaskIsAlreadyOnAndClosedTasks() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "- [ ] past 📅 2026-10-01 ^past\n- [ ] none ^none\n- [/] doing 📅 2026-10-01 ^doing\n"
            + "- [ ] today 📅 2026-10-03 ^today\n- [ ] tomorrow 📅 2026-10-04 ^tomorrow\n"
            + "- [ ] monday 📅 2026-10-05 ^monday\n- [x] done 📅 2026-10-01 ✅ 2026-10-02 ^done\n"
            + "- [X] upper 📅 2026-10-03 ^upper\n- [-] dropped 📅 2026-10-01 ^dropped\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let all: [TaskMoveDestination] = [.today, .tomorrow, .nextWeek]
        #expect(try destinations("past", in: context) == all)
        #expect(try destinations("none", in: context) == all)
        #expect(try destinations("doing", in: context) == all)
        #expect(try destinations("today", in: context) == [.tomorrow, .nextWeek])
        #expect(try destinations("tomorrow", in: context) == [.today, .nextWeek])
        #expect(try destinations("monday", in: context) == [.today, .tomorrow])
        #expect(try destinations("done", in: context).isEmpty)
        #expect(try destinations("upper", in: context).isEmpty)
        #expect(try destinations("dropped", in: context).isEmpty)
        let week = WeekStartTests.calendar(firstWeekday: 2)
        let dates = TaskMove.options(for: try context.row("past"), on: context.today, calendar: week).map(\.date)
        #expect(dates == [context.today, CalendarDate("2026-10-04"), CalendarDate("2026-10-05")])
    }

    /// Saturday on a Sunday week: tomorrow and next week are both Sunday, so only tomorrow is offered.
    @Test func sundayWeekSaturdayKeepsTheEarlierMoveWhenDatesMatch() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try Data("- [ ] open ^open\n- [ ] here 📅 2026-10-03 ^here\n".utf8).write(to: context.file)
        await context.store.refresh()
        let saturday = CalendarDate("2026-10-03")!
        #expect(saturday.weekday == 5)
        #expect(context.today == saturday)
        let sundayWeek = WeekStartTests.calendar(firstWeekday: 1)
        let open = TaskMove.options(for: try context.row("open"), on: saturday, calendar: sundayWeek)
        #expect(open.map(\.destination) == [.today, .tomorrow])
        #expect(open.map(\.date) == [saturday, CalendarDate("2026-10-04")])
        let here = TaskMove.options(for: try context.row("here"), on: saturday, calendar: sundayWeek)
        #expect(here.map(\.destination) == [.tomorrow])
        #expect(here.map(\.date) == [CalendarDate("2026-10-04")])
        let mondayWeek = WeekStartTests.calendar(firstWeekday: 2)
        let monday = TaskMove.options(for: try context.row("open"), on: saturday, calendar: mondayWeek)
        #expect(monday.map(\.destination) == [.today, .tomorrow, .nextWeek])
        #expect(
            monday.map(\.date) == [saturday, CalendarDate("2026-10-04"), CalendarDate("2026-10-05")])
    }

    @Test func noticeCountsEveryOutcomeAndLeavesOutZeroes() {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "tr_TR")] {
            let all = TaskMoveReport(moved: 5, unchanged: 3, failed: 2).text(locale: locale)
            #expect(numbers(all) == ["5", "3", "2"])
            #expect(numbers(TaskMoveReport(moved: 4).text(locale: locale)) == ["4"])
            #expect(numbers(TaskMoveReport(unchanged: 6).text(locale: locale)) == ["6"])
            #expect(numbers(TaskMoveReport(failed: 7).text(locale: locale)) == ["7"])
            #expect(TaskMoveReport().text(locale: locale) == nil)
            // Three different sentences, not one repeated.
            let parts = Set(
                [
                    TaskMoveReport(moved: 2), TaskMoveReport(unchanged: 2), TaskMoveReport(failed: 2),
                ].compactMap { $0.text(locale: locale) })
            #expect(parts.count == 3)
        }
        #expect(!TaskMoveReport(moved: 2).isPartial)
        #expect(TaskMoveReport(moved: 2, unchanged: 1).isPartial)
        #expect(TaskMoveReport(moved: 2, failed: 1).isPartial)
    }

    private func typed(
        _ text: String, _ today: CalendarDate, _ languages: [DateParsing.Language], in context: TaskTestContext
    ) -> CalendarDate? {
        let model = QuickEntryModel(store: context.store, today: { today })
        model.languages = languages
        model.mode = .task
        model.text = text
        return model.dueDate
    }

    private func destinations(_ text: String, in context: TaskTestContext) throws -> [TaskMoveDestination] {
        let week = WeekStartTests.calendar(firstWeekday: 2)
        return TaskMove.options(for: try context.row(text), on: context.today, calendar: week).map(\.destination)
    }

    private func numbers(_ text: String?) -> [String] {
        (text ?? "").split(whereSeparator: { !$0.isNumber }).map(String.init)
    }
}

/// Quick entry, the App Intent and the task menu read week expressions from the calendar they are
/// given, never from the process: CI and a developer's machine start their weeks on different days.
@MainActor
struct WeekStartTests {
    nonisolated static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// `firstWeekday`, then next week's first day seen from Saturday 3, Sunday 4 and Monday 5 October 2026.
    nonisolated static let weeks: [(Int, [String])] = [
        (2, ["2026-10-05", "2026-10-05", "2026-10-12"]),
        (1, ["2026-10-04", "2026-10-11", "2026-10-11"]),
        // The parser knows two week starts; a Saturday week is read as a Sunday week.
        (7, ["2026-10-04", "2026-10-11", "2026-10-11"]),
    ]

    @Test(arguments: weeks)
    func menuAndQuickEntryGiveTheSameNextWeekOnEachCalendar(firstWeekday: Int, expected: [String]) throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let calendar = Self.calendar(firstWeekday: firstWeekday)
        let first = try #require(CalendarDate("2026-10-03"))
        for (offset, day) in expected.enumerated() {
            let today = try #require(first.addingDays(offset))
            #expect(TaskMove.date(.nextWeek, today: today, calendar: calendar) == CalendarDate(day), "\(today)")
        }
        for offset in 0..<14 {
            let today = try #require(first.addingDays(offset))
            let menu = try #require(TaskMove.date(.nextWeek, today: today, calendar: calendar))
            // The first day of the calendar's week, one to seven days ahead.
            let weekday = firstWeekday == 2 ? 0 : 6
            #expect(menu.weekday == weekday && menu > today && menu <= today.addingDays(7)!, "\(today)")
            let typed = { (text: String, languages: [DateParsing.Language]) -> CalendarDate? in
                let model = QuickEntryModel(store: context.store, today: { today })
                model.languages = languages
                model.calendar = calendar
                model.mode = .task
                model.text = text
                return model.dueDate
            }
            #expect(typed("call haftaya", [.turkish]) == menu, "\(today)")
            #expect(typed("call gelecek hafta", [.turkish]) == menu, "\(today)")
            #expect(typed("call next week", [.english]) == menu, "\(today)")
            // A weekday of next week is counted from the same first day.
            #expect(typed("call haftaya salı", [.turkish]) == menu.addingDays(firstWeekday == 2 ? 1 : 2), "\(today)")
            #expect(typed("her gün call haftaya", [.turkish]) == menu, "\(today)")
            // The weekend and tomorrow do not depend on where the week starts.
            #expect(typed("call bu hafta sonu", [.turkish])?.weekday == 5, "\(today)")
            #expect(
                TaskMove.date(.tomorrow, today: today, calendar: calendar) == typed("call yarın", [.turkish]),
                "\(today)")
        }
    }

    @Test(arguments: weeks)
    func intentWritesTheDayTheMenuGives(firstWeekday: Int, expected: [String]) async throws {
        let calendar = Self.calendar(firstWeekday: firstWeekday)
        for (offset, day) in expected.enumerated() {
            let context = try TaskTestContext()
            defer { context.clean() }
            await context.start()
            let today = try #require(CalendarDate("2026-10-03")?.addingDays(offset))
            let instant = LocalDay.instant(for: today)
            let actions = IntentActions(store: context.store, now: { instant }, permitsStart: { true })
            actions.calendar = calendar
            _ = try await actions.addTask(text: "haftaya plan")
            _ = try await actions.addTask(text: "every day review next week")
            let file = context.root.appendingPathComponent("journal/\(today).md")
            let tasks = RawDocument(bytes: try Data(contentsOf: file)).bodyLines.tasks
            #expect(tasks.map(\.text) == ["plan", "review"])
            #expect(tasks.map(\.dueDate) == [CalendarDate(day), CalendarDate(day)], "\(today)")
            #expect(TaskMove.date(.nextWeek, today: today, calendar: calendar) == CalendarDate(day))
            // The menu of the written task reads the same calendar: the day it is already on is not offered.
            let row = try #require(context.store.content.tasks.first { $0.sourceText == "plan" })
            let offered = TaskMove.options(for: row, on: today, calendar: calendar).map(\.date)
            #expect(offered == [today, today.addingDays(1)].filter { $0 != row.due }, "\(today)")
        }
    }
}

@MainActor
struct TaskMoveWriteTests {
    /// The path a menu or VoiceOver move takes: read the task, then write its due date.
    private func move(_ text: String, to date: CalendarDate, in context: TaskTestContext) async throws -> Bool {
        let editor = TaskEditorModel(store: context.store, row: try context.row(text))
        await editor.load()
        guard editor.target != nil else { return false }
        return await editor.setDue(date)
    }

    private func sameRows(in context: TaskTestContext) -> [TaskRow] {
        context.store.content.tasks.filter { $0.sourceText == "same" }.sorted { $0.sourceLine < $1.sourceLine }
    }

    @Test func moveRewritesOnlyTheDueField() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let lines = [
            "\u{FEFF}## Tasks",
            "- [ ] call [[Ada]] 📅 2026-10-01 ⏫ 🔁 every week #project/demo ^move",
            "  keep",
            "- [ ] bare [[Ada|A.]] ⏫ 🔁 every day #project/demo #tag ^bare",
            "\tchild",
            "",
            "    - nested note 📅 2026-01-01",
            "* [/] span 🛫 2026-09-20 📅 2026-10-02 🧪 odd ^span",
            "- [ ] parent 📅 2026-10-01 ^parent",
            "    - [ ] inner 📅 2026-10-01 🔽 ^inner",
            "- [x] done 📅 2026-10-01 ✅ 2026-10-02 ^done",
            "- [ ] plain 🔽 ^stay",
            "tail without newline",
        ]
        let source = lines.joined(separator: "\r\n")
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let tomorrow = try #require(TaskMove.date(.tomorrow, today: context.today))
        #expect(try await move("call [[Ada]]", to: context.today, in: context))
        #expect(try await move("bare [[Ada|A.]] #tag", to: context.today, in: context))
        #expect(try await move("span 🧪 odd", to: tomorrow, in: context))
        #expect(try await move("inner", to: context.today, in: context))
        var expected = lines
        expected[1] = "- [ ] call [[Ada]] 📅 2026-10-03 ⏫ 🔁 every week #project/demo ^move"
        expected[3] = "- [ ] bare [[Ada|A.]] ⏫ 🔁 every day #project/demo #tag 📅 2026-10-03 ^bare"
        expected[7] = "* [/] span 🛫 2026-09-20 📅 2026-10-04 🧪 odd ^span"
        expected[9] = "    - [ ] inner 📅 2026-10-03 🔽 ^inner"
        #expect(try Data(contentsOf: context.file) == Data(expected.joined(separator: "\r\n").utf8))
        // File first, then the index: the rows already carry the new dates.
        #expect(try context.row("call [[Ada]]").due == context.today)
        #expect(try context.row("call [[Ada]]").recurrence?.rule == "every week")
        #expect(try context.row("span 🧪 odd").due == tomorrow)
        #expect(try context.row("span 🧪 odd").start == CalendarDate("2026-09-20"))
        #expect(try context.row("parent").due == CalendarDate("2026-10-01"))
    }

    @Test func moveGivesAnIdentifierOnlyToTheLineItChanges() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try Data("- [ ] first 📅 2026-10-01\n- [ ] second 📅 2026-10-01\n".utf8).write(to: context.file)
        await context.store.refresh()
        #expect(try await move("second", to: context.today, in: context))
        let text = String(decoding: try Data(contentsOf: context.file), as: UTF8.self)
        let prefix = "- [ ] first 📅 2026-10-01\n- [ ] second 📅 2026-10-03 ^"
        #expect(text.hasPrefix(prefix))
        let rest = text.dropFirst(prefix.count)
        #expect(rest.count == 7 && rest.last == "\n")
        #expect(rest.dropLast().allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) })
    }

    @Test func bulkMoveKeepsGoingWhenOneTaskChanged() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "- [ ] one 📅 2026-10-01 ^one\n- [ ] two 📅 2026-10-01 ^two\n"
            + "- [ ] three 📅 2026-10-01 🔁 every week ^three\n- [x] done 📅 2026-10-01 ✅ 2026-10-02 ^done\n"
            + "- [ ] four 📅 2026-10-01 ^four\n- [ ] here 📅 2026-10-03 ^here\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let groups = await DayTasksModel.loaded(store: context.store, day: context.today, isToday: true).groups
        #expect(groups.overdue.map(\.sourceText).sorted() == ["four", "one", "three", "two"])
        let rows = try ["one", "two", "three", "done", "four", "here"].map { try context.row($0) }
        let edited = Data(source.replacingOccurrences(of: "- [ ] two ", with: "- [ ] altered ").utf8)
        try edited.write(to: context.file)
        let report = await TaskMove.apply(rows, to: context.today, in: context.store)
        // Closed and already-there rows are not part of the count.
        #expect(report == TaskMoveReport(moved: 3, unchanged: 1, failed: 0, failureText: nil))
        let expected =
            "- [ ] one 📅 2026-10-03 ^one\n- [ ] altered 📅 2026-10-01 ^two\n"
            + "- [ ] three 📅 2026-10-03 🔁 every week ^three\n- [x] done 📅 2026-10-01 ✅ 2026-10-02 ^done\n"
            + "- [ ] four 📅 2026-10-03 ^four\n- [ ] here 📅 2026-10-03 ^here\n"
        #expect(try Data(contentsOf: context.file) == Data(expected.utf8))
        #expect(try context.row("four").due == context.today)
        #expect(try context.row("altered").due == CalendarDate("2026-10-01"))
    }

    @Test func bulkMoveFollowsShiftedLinesAndSkipsClosedOrRemovedTasks() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "- [ ] one 📅 2026-10-01 ^one\n- [ ] gone 📅 2026-10-01 ^gone\n- [ ] closed 📅 2026-10-01 ^closed\n"
            + "- [ ] two 📅 2026-10-01 ^two\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let rows = try ["one", "gone", "closed", "two"].map { try context.row($0) }
        // Outside the app: lines added above, one task deleted, one completed.
        let outside =
            "# Heading\n\n- 09:00 an event ^event\n- [ ] one 📅 2026-10-01 ^one\n"
            + "- [x] closed 📅 2026-10-01 ✅ 2026-10-03 ^closed\n- [ ] two 📅 2026-10-01 ^two\n"
        try Data(outside.utf8).write(to: context.file)
        let report = await TaskMove.apply(rows, to: context.today, in: context.store)
        #expect(report == TaskMoveReport(moved: 2, unchanged: 2, failed: 0, failureText: nil))
        let expected =
            "# Heading\n\n- 09:00 an event ^event\n- [ ] one 📅 2026-10-03 ^one\n"
            + "- [x] closed 📅 2026-10-01 ✅ 2026-10-03 ^closed\n- [ ] two 📅 2026-10-03 ^two\n"
        #expect(try Data(contentsOf: context.file) == Data(expected.utf8))
    }

    /// Two tasks that read the same cannot be told apart once their lines move: the app writes only the
    /// one it can pin down and reports the other, never a guess.
    @Test func bulkMoveNeverGuessesBetweenIdenticalTasks() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "- [ ] same 📅 2026-10-01 ^a\n- [ ] same 📅 2026-10-01 ^a\n- [ ] other 📅 2026-10-01 ^b\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let rows = sameRows(in: context)
        #expect(rows.count == 2)
        let inPlace = await TaskMove.apply(rows, to: context.today, in: context.store)
        #expect(inPlace.moved == 2 && inPlace.unchanged == 0 && inPlace.failed == 0)
        let text = String(decoding: try Data(contentsOf: context.file), as: UTF8.self)
        let written = text.split(separator: "\n").map(String.init)
        #expect(written.count == 3)
        #expect(written[0].hasPrefix("- [ ] same 📅 2026-10-03 ^"))
        #expect(written[1].hasPrefix("- [ ] same 📅 2026-10-03 ^"))
        #expect(written[2] == "- [ ] other 📅 2026-10-01 ^b")

        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let again = sameRows(in: context)
        try Data(("note\n" + source).utf8).write(to: context.file)
        let shifted = await TaskMove.apply(again, to: context.today, in: context.store)
        #expect(shifted.moved + shifted.unchanged == 2 && shifted.unchanged >= 1 && shifted.failed == 0)
        let after = String(decoding: try Data(contentsOf: context.file), as: UTF8.self).split(separator: "\n")
        #expect(after.count == 4 && after[0] == "note" && after[3] == "- [ ] other 📅 2026-10-01 ^b")
        #expect(after[1...2].filter { $0.hasPrefix("- [ ] same 📅 2026-10-03") }.count == shifted.moved)
        #expect(after[1...2].filter { $0 == "- [ ] same 📅 2026-10-01 ^a" }.count == shifted.unchanged)
    }

    @Test func bulkMoveReportsAMissingFileApartFromAChangedTask() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let other = context.root.appendingPathComponent("journal/2026-10-02.md")
        try Data("- [ ] kept 📅 2026-10-01 ^kept\n".utf8).write(to: context.file)
        try Data("- [ ] lost 📅 2026-10-01 ^lost\n".utf8).write(to: other)
        await context.store.refresh()
        let rows = try ["lost", "kept"].map { try context.row($0) }
        try FileManager.default.removeItem(at: other)
        let report = await TaskMove.apply(rows, to: context.today, in: context.store)
        #expect(report.moved == 1 && report.unchanged == 0 && report.failed == 1)
        #expect(report.failureText?.isEmpty == false)
        #expect(report.failureText != DayEditError.message(for: VaultStoreError.staleTarget))
        #expect(try Data(contentsOf: context.file) == Data("- [ ] kept 📅 2026-10-03 ^kept\n".utf8))
        #expect(!FileManager.default.fileExists(atPath: other.path))
    }

    @Test func bulkMoveWithNothingToMoveWritesNothing() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "- [ ] here 📅 2026-10-03 ^here\n- [x] done 📅 2026-10-01 ✅ 2026-10-02 ^done\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let stamp = try FileManager.default.attributesOfItem(atPath: context.file.path)[.modificationDate] as? Date
        let rows = try ["here", "done"].map { try context.row($0) }
        for list in [[], rows] {
            let report = await TaskMove.apply(list, to: context.today, in: context.store)
            #expect(report == TaskMoveReport())
            #expect(report.text(locale: Locale(identifier: "en_US")) == nil)
        }
        #expect(try Data(contentsOf: context.file) == Data(source.utf8))
        #expect(
            try FileManager.default.attributesOfItem(atPath: context.file.path)[.modificationDate] as? Date == stamp)
    }
}
