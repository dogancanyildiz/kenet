import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Kenet

/// Mac Today desk panel selection and hour-grid bounds (`docs/screens.md`, "Bugün sağ paneli").
struct TodayDeskPlanTests {
    private let day = CalendarDate("2026-09-20")!
    private let earlier = CalendarDate("2026-09-14")!

    @Test func nextEventAndTaskAreTheSoonestAtOrAfterNow() throws {
        let events = [
            try event(1, hour: 11, minute: 0, text: "Sabah"),
            try event(2, hour: 16, minute: 0, text: "Sergi"),
            try event(3, hour: 9, minute: 30, text: "Temizlik"),
        ]
        let tasks = [
            try task(1, text: "17:00 Yemek planı"),
            try task(2, text: "10:00 Erken iş"),
            try task(3, text: "Saatsiz iş"),
        ]
        let plan = TodayDeskPlan(
            events: events, openTasks: tasks, carriedOver: [], nowHour: 14, nowMinute: 30)
        #expect(plan.nextEvent?.text.plainText == "Sergi")
        #expect(plan.nextTimedTask?.task.text.plainText == "17:00 Yemek planı")
        #expect(plan.nextTimedTask?.time.hour == 17)
        #expect(plan.timedEvents.map(\.text.plainText) == ["Temizlik", "Sabah", "Sergi"])
        #expect(plan.untimedTasks.map(\.text.plainText) == ["Saatsiz iş"])
    }

    @Test func nextSectionsHideWhenNothingRemains() throws {
        let events = [try event(1, hour: 9, minute: 0, text: "Geçmiş")]
        let plan = TodayDeskPlan(
            events: events, openTasks: [try task(1, text: "08:00 Erken")], carriedOver: [],
            nowHour: 18, nowMinute: 0)
        #expect(plan.nextEvent == nil)
        #expect(plan.nextTimedTask == nil)
    }

    @Test func carriedPreviewShowsTwoRowsAndARemainder() throws {
        let carried = try (1...5).map { try task($0, text: "Devreden \($0)", due: earlier) }
        let plan = TodayDeskPlan(
            events: [], openTasks: [], carriedOver: carried, nowHour: 12, nowMinute: 0)
        #expect(plan.carriedPreview.map(\.text.plainText) == ["Devreden 1", "Devreden 2"])
        #expect(plan.hiddenCarriedCount == 3)
        let few = TodayDeskPlan(
            events: [], openTasks: [], carriedOver: Array(carried.prefix(2)), nowHour: 12,
            nowMinute: 0)
        #expect(few.hiddenCarriedCount == 0)
    }

    @Test func carriedTimedTasksStayOffTheHourGrid() throws {
        let carried = try task(1, text: "09:00 Eski iş", due: earlier)
        let today = try task(2, text: "15:00 Bugünkü")
        let plan = TodayDeskPlan(
            events: [], openTasks: [carried, today], carriedOver: [carried], nowHour: 8,
            nowMinute: 0)
        #expect(plan.timedTasks.map(\.task.text.plainText) == ["15:00 Bugünkü"])
        #expect(plan.nextTimedTask?.task.text.plainText == "15:00 Bugünkü")
        #expect(plan.carriedPreview.map(\.text.plainText) == ["09:00 Eski iş"])
    }

    @Test func hourRangeWidensWithRecords() throws {
        #expect(TimelineDayHours.range(forHours: []) == 9...18)
        let early = TodayDeskPlan(
            events: [try event(1, hour: 5, minute: 0, text: "Erken")], openTasks: [], carriedOver: [],
            nowHour: 12, nowMinute: 0)
        #expect(early.hourRange == 5...18)
        let late = TodayDeskPlan(
            events: [], openTasks: [try task(1, text: "23:00 Geç")], carriedOver: [], nowHour: 12,
            nowMinute: 0)
        #expect(late.hourRange == 9...23)
    }

    @Test func panelShowsOnlyWhenDetailIsWideEnough() {
        #expect(TodayDeskPlan.showsPanel(detailWidth: 979) == false)
        #expect(TodayDeskPlan.showsPanel(detailWidth: 980) == true)
        #expect(
            TodayDeskPlan.panelMinDetailWidth == InkSpacing.macPageWidth + ShellStyle.todayPanelWidth)
    }

    /// The grid is the only place for timed records: the page lists keep the untimed ones.
    @Test func dayListsKeepOnlyUntimedRecords() throws {
        let events = [
            try event(1, hour: 11, minute: 0, text: "Sabah"),
            untimedEvent(2, text: "Saatsiz not"),
        ]
        let carried = try task(1, text: "09:00 Eski iş", due: earlier)
        let timed = try task(2, text: "15:00 Bugünkü")
        let untimed = try task(3, text: "Saatsiz iş")
        let plan = TodayDeskPlan(
            events: events, openTasks: [carried, timed, untimed], carriedOver: [carried],
            nowHour: 8, nowMinute: 0)
        #expect(plan.dayListEvents.map(\.text.plainText) == ["Saatsiz not"])
        #expect(plan.timedEvents.map(\.text.plainText) == ["Sabah"])
        #expect(plan.gridTaskIDs == [timed.id])

        let rows: [TodayPresentation.Row] = [
            .task(carried), .carriedOverDisclosure("1 devreden daha"), .task(timed), .task(untimed),
            .completedDisclosure("2 tamamlandı"),
        ]
        // Carried-over timed tasks are not on the grid, so the page keeps them.
        #expect(
            plan.dayListTaskRows(rows).map(\.id) == [
                carried.id, "carried:1 devreden daha", untimed.id, "completed:2 tamamlandı",
            ])
    }

    @Test func dayListTaskCounterLeavesOutGridTasks() throws {
        let timed = try task(1, text: "15:00 Bugünkü")
        let untimed = try task(2, text: "Saatsiz iş")
        var groups = TaskGroups(rows: [], on: day, isToday: true)
        groups.dated = [timed, untimed]
        let presentation = TodayPresentation(
            day: DaySummary(empty: day), groups: groups,
            goals: [], goalStatuses: [:], goalStatusesDay: nil, today: day,
            locale: Locale(identifier: "tr_TR"), calendar: Calendar(identifier: .gregorian))
        let plan = TodayDeskPlan(
            events: [], openTasks: presentation.openTasks, carriedOver: [], nowHour: 8, nowMinute: 0)
        #expect(presentation.counter(for: .tasks) == "2")
        #expect(plan.dayListTaskCounter(presentation) == "1")
        let allTimed = TodayDeskPlan(
            events: [], openTasks: [timed], carriedOver: [], nowHour: 8, nowMinute: 0)
        #expect(allTimed.dayListTaskRows([.task(timed)]).isEmpty, "an empty list draws no section")
    }

    /// Folded under the grid, the page above already shows goals and carried-over tasks.
    @Test func foldedPanelLeavesGoalsAndCarriedOverToThePage() {
        #expect(
            TodayDeskPlan.panelSections(isFolded: true) == [.nextEvent, .nextTask, .onThisDay, .closeDay])
        #expect(
            TodayDeskPlan.panelSections(isFolded: false) == [
                .nextEvent, .nextTask, .goals, .carriedOver, .onThisDay, .closeDay,
            ])
    }

    /// A task card carries its completion box (same state as the day page's task row); an event
    /// card has none.
    @Test func taskCardsCarryACompletionBoxAndEventCardsDoNot() throws {
        let event = try event(1, hour: 10, minute: 0, text: "Toplantı")
        let open = try task(2, text: "10:30 Sunum provası", priority: "⏫")
        let plan = TodayDeskPlan(
            events: [event], openTasks: [open], carriedOver: [], nowHour: 8, nowMinute: 0)
        let cards = try #require(plan.gridCardsByHour[10])
        #expect(cards.count == 2)
        #expect(cards.first?.box == nil, "an event card has no box")
        let box = try #require(cards.last?.box)
        #expect(box == TaskBoxPresentation(row: open).state)
        #expect(box.status == .todo)
        #expect(box.priority == .high)
        #expect(box.priorityGlyph == "!!")
    }

    /// Completed today (or being completed now), a grid task stays where it was, drawn done; it is
    /// no longer the panel's next task. Carried-over and other days' completed tasks stay off.
    @Test func tasksCompletedTodayStayOnTheGridAsDone() throws {
        let done = try task(1, text: "11:00 Bitti", rawStatus: "x")
        let completing = try task(2, text: "12:00 Şimdi bitiyor")
        let next = try task(3, text: "13:00 Sıradaki")
        let carriedDone = try task(4, text: "09:00 Eski iş", due: earlier, rawStatus: "x")
        let otherDay = try task(
            5, text: "14:00 Başka gün", due: nil, rawStatus: "x", file: "journal/\(earlier).md")
        let cancelled = try task(6, text: "15:00 Vazgeçildi", rawStatus: "-")
        let plan = TodayDeskPlan(
            events: [], openTasks: [next], carriedOver: [], nowHour: 10, nowMinute: 0,
            completedTasks: [done, completing, carriedDone, otherDay, cancelled], day: day)
        #expect(
            plan.timedTasks.map(\.task.text.plainText) == ["11:00 Bitti", "12:00 Şimdi bitiyor", "13:00 Sıradaki"])
        #expect(plan.completedTaskIDs == [done.id, completing.id])
        #expect(plan.taskBox(for: done).isCompleted)
        #expect(
            plan.taskBox(for: completing).isCompleted, "a row still open in the file draws done while it is written")
        #expect(!plan.taskBox(for: next).isCompleted)
        #expect(plan.nextTimedTask?.task.id == next.id)
        #expect(plan.gridCardsByHour[12]?.first?.box?.isCompleted == true)
        #expect(plan.untimedTasks.isEmpty)
    }

    @Test func dayScheduleHelperReadsClockPrefix() {
        #expect(DaySchedulePresentation.extractLeadingTime(from: "17:00 Yemek")?.hour == 17)
        #expect(DaySchedulePresentation.extractLeadingTime(from: "17:00 Yemek")?.minute == 0)
        #expect(DaySchedulePresentation.strippingLeadingTime(from: "17:00 Yemek") == "Yemek")
        #expect(DaySchedulePresentation.extractLeadingTime(from: "Yemek") == nil)
    }

    private func event(_ id: Int, hour: Int, minute: Int, text: String) throws -> EventRow {
        let time = try #require(
            DaySchedulePresentation.extractLeadingTime(
                from: String(format: "%02d:%02d x", hour, minute)))
        return EventRow(
            id: id, time: time, text: LinkedText(spans: [.init(text: text, destination: nil)]),
            sourceLine: id, sourceEnd: id, sourceText: text, sourceIdentifier: nil)
    }

    private func untimedEvent(_ id: Int, text: String) -> EventRow {
        EventRow(
            id: id, time: nil, text: LinkedText(spans: [.init(text: text, destination: nil)]),
            sourceLine: id, sourceEnd: id, sourceText: text, sourceIdentifier: nil)
    }

    private func task(
        _ id: Int, text: String, due: CalendarDate? = nil, rawStatus: String = " ",
        priority: String? = nil, file: String? = nil
    ) throws -> TaskRow {
        var fields: [String: Any] = [
            "file": file ?? "journal/\(day).md", "ordinal": id, "kind": "task", "firstLine": id + 1,
            "lastLine": id + 1, "text": text, "section": "Tasks", "rawStatus": rawStatus,
            "ownsIdentifier": false,
        ]
        if file == nil || due != nil { fields["dueDate"] = (due ?? day).description }
        if let priority { fields["priority"] = priority }
        let block = try JSONDecoder().decode(
            IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        return TaskRow(row: block, links: [])
    }
}
