import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

/// Mac Today desk panel selection and hour-grid bounds (`docs/screens.md`, "Bugün sağ paneli").
struct TodayDeskPlanTests {
    private let day = CalendarDate("2026-09-20")!

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
        let carried = try (1...5).map { try task($0, text: "Devreden \($0)") }
        let plan = TodayDeskPlan(
            events: [], openTasks: [], carriedOver: carried, nowHour: 12, nowMinute: 0)
        #expect(plan.carriedPreview.map(\.text.plainText) == ["Devreden 1", "Devreden 2"])
        #expect(plan.hiddenCarriedCount == 3)
        let few = TodayDeskPlan(
            events: [], openTasks: [], carriedOver: Array(carried.prefix(2)), nowHour: 12,
            nowMinute: 0)
        #expect(few.hiddenCarriedCount == 0)
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

    @Test func extractLeadingTimeReadsClockPrefix() {
        #expect(TodayDeskPlan.extractLeadingTime(from: "17:00 Yemek")?.hour == 17)
        #expect(TodayDeskPlan.extractLeadingTime(from: "17:00 Yemek")?.minute == 0)
        #expect(TodayDeskPlan.strippingLeadingTime(from: "17:00 Yemek") == "Yemek")
        #expect(TodayDeskPlan.extractLeadingTime(from: "Yemek") == nil)
    }

    private func event(_ id: Int, hour: Int, minute: Int, text: String) throws -> EventRow {
        let time = try #require(
            TodayDeskPlan.extractLeadingTime(from: String(format: "%02d:%02d x", hour, minute)))
        return EventRow(
            id: id, time: time, text: LinkedText(spans: [.init(text: text, destination: nil)]),
            sourceLine: id, sourceEnd: id, sourceText: text, sourceIdentifier: nil)
    }

    private func task(_ id: Int, text: String) throws -> TaskRow {
        let fields: [String: Any] = [
            "file": "journal/\(day).md", "ordinal": id, "kind": "task", "firstLine": id + 1,
            "lastLine": id + 1, "text": text, "section": "Tasks", "rawStatus": " ",
            "ownsIdentifier": false, "dueDate": day.description,
        ]
        let block = try JSONDecoder().decode(
            IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        return TaskRow(row: block, links: [])
    }
}
