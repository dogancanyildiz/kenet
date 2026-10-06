import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

struct TodayPresentationTests {
    private let day = CalendarDate("2026-10-06")!
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        return value
    }

    private func row(_ id: Int, status: String = " ", due: String? = nil, priority: String? = nil) throws -> TaskRow {
        var fields: [String: Any] = [
            "file": "journal/2026-10-06.md", "ordinal": id, "kind": "task", "firstLine": id + 1,
            "lastLine": id + 1, "text": "Sample", "section": "Tasks", "rawStatus": status,
            "ownsIdentifier": false,
        ]
        fields["dueDate"] = due
        fields["priority"] = priority
        if status == "x" { fields["doneDate"] = day.description }
        let block = try JSONDecoder().decode(IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        return TaskRow(row: block, links: [])
    }

    private func summary(events: Int = 0, date: CalendarDate? = nil) throws -> DaySummary {
        let text = try row(100).text
        return DaySummary(
            id: "sample", date: date ?? day,
            events: (0..<events).map {
                EventRow(
                    id: $0, time: nil, text: text, sourceLine: $0, sourceEnd: $0 + 1,
                    sourceText: "Sample", sourceIdentifier: nil)
            }, journal: [])
    }

    private func make(
        events: Int = 0, tasks: Int = 0, goals: Int = 0, locale: String,
        groups: TaskGroups? = nil, completed: [TaskRow] = []
    ) throws -> TodayPresentation {
        let definitions = (0..<goals).map {
            GoalDefinition(id: "goal\($0)", key: "goal\($0)", name: "Sample", period: .day, kind: .boolean)!
        }
        return try TodayPresentation(
            day: summary(events: events),
            groups: groups
                ?? TaskGroups(
                    rows: (0..<tasks).map { try row($0) }, on: day, isToday: true),
            goals: definitions, goalStatuses: [:], today: day, locale: Locale(identifier: locale),
            calendar: calendar, completedTasks: completed)
    }

    @Test(arguments: ["tr_TR", "en_US"])
    func bylineOmitsZeroPartsAndPluralizes(_ language: String) throws {
        let turkish = language == "tr_TR"
        let cases: [(Int, Int, Int, String?)] = [
            (0, 0, 0, nil),
            (3, 4, 2, turkish ? "3 olay · 4 görev ve 2 hedef kaldı" : "3 events · 4 tasks and 2 goals remaining"),
            (3, 0, 2, turkish ? "3 olay · 2 hedef kaldı" : "3 events · 2 goals remaining"),
            (0, 4, 0, turkish ? "4 görev kaldı" : "4 tasks remaining"),
            (3, 0, 0, turkish ? "3 olay" : "3 events"),
            (1, 1, 1, turkish ? "1 olay · 1 görev ve 1 hedef kaldı" : "1 event · 1 task and 1 goal remaining"),
            (0, 0, 1, turkish ? "1 hedef kaldı" : "1 goal remaining"),
            (0, 1, 1, turkish ? "1 görev ve 1 hedef kaldı" : "1 task and 1 goal remaining"),
            (1, 1, 0, turkish ? "1 olay · 1 görev kaldı" : "1 event · 1 task remaining"),
        ]
        for (events, tasks, goals, expected) in cases {
            #expect(try make(events: events, tasks: tasks, goals: goals, locale: language).byline == expected)
        }
    }

    @Test(arguments: [0, 3, 4, 10])
    func carriedOverLimitPreservesInputOrder(_ count: Int) throws {
        var groups = TaskGroups(rows: [], on: day, isToday: true)
        groups.overdue = try (0..<count).map { try row($0, due: "2026-09-\(String(format: "%02d", $0 + 1))") }
        for language in ["tr_TR", "en_US"] {
            var value = try make(locale: language, groups: groups)
            #expect(value.carriedOverTasks.map(\.id) == Array(groups.overdue.prefix(3)).map(\.id))
            #expect(value.remainingTaskCount == count)
            #expect(value.hiddenCarriedOverCount == max(0, count - 3))
            let expected =
                count > 3
                ? (language == "tr_TR" ? "\(count - 3) devreden daha" : "\(count - 3) more carried over") : nil
            #expect(value.carriedOverDisclosure == expected)
            value.isCarriedOverExpanded = true
            #expect(value.carriedOverTasks.map(\.id) == groups.overdue.map(\.id))
            #expect(value.carriedOverDisclosure == nil)
        }
    }

    @Test(arguments: [0, 1, 2, 10])
    func completedRowsFoldAtEndAndDoNotCountAsRemaining(_ count: Int) throws {
        let done = try (0..<count).map { try row($0 + 100, status: "x") }
        for language in ["tr_TR", "en_US"] {
            var value = try make(tasks: 1, locale: language, completed: done)
            #expect(value.remainingTaskCount == 1)
            #expect(value.completedTaskCount == count)
            #expect(value.completedTaskRows.count == (count <= 1 ? count : 0))
            let expected =
                count > 1
                ? (language == "tr_TR" ? "\(count) görev tamamlandı" : "\(count) tasks completed") : nil
            #expect(value.completedDisclosure == expected)
            value.isCompletedExpanded = true
            #expect(value.completedTaskRows.map(\.id) == done.map(\.id))
            #expect(Array(value.taskRows.suffix(count)).map(\.id) == done.map(\.id))
            #expect(value.completedDisclosure == nil)
        }
    }

    @Test(arguments: ["tr_TR", "en_US"])
    func headlineAndCarriedDateRespectLocaleAndYear(_ language: String) throws {
        let locale = Locale(identifier: language)
        let value = try make(locale: language)
        #expect(value.headline == (language == "tr_TR" ? "6 Ekim Salı" : "Tuesday, October 6"))
        let september = TodayPresentation.carriedOverDate(
            CalendarDate("2026-09-30")!, today: day, locale: locale, calendar: calendar)
        #expect(september == (language == "tr_TR" ? "30 Eyl'den" : "from Sep 30"))
        let previous = CalendarDate("2025-12-31")!
        let now = CalendarDate("2026-01-02")!
        let past = try TodayPresentation(
            day: summary(date: previous), groups: TaskGroups(rows: [], on: previous, isToday: false),
            goals: [], goalStatuses: [:], today: now, locale: locale, calendar: calendar)
        #expect(past.headline == (language == "tr_TR" ? "31 Aralık 2025 Çarşamba" : "Wednesday, December 31, 2025"))
        #expect(
            TodayPresentation.carriedOverDate(previous, today: now, locale: locale, calendar: calendar)
                == (language == "tr_TR" ? "31 Ara 2025'den" : "from Dec 31, 2025"))
    }

    @Test(arguments: ["tr_TR", "en_US"])
    func countersUseAllOpenGroupsAndDailyGoals(_ language: String) throws {
        let daily = (0..<3).map {
            GoalDefinition(id: "g\($0)", key: "g\($0)", name: "Sample", period: .day, kind: .boolean)!
        }
        let weekly = GoalDefinition(id: "week", key: "week", name: "Sample", period: .week, kind: .boolean)!
        let status = GoalProgress.compute(
            definition: daily[0], logs: [GoalLog(day: day, value: .boolean(true))], today: day)
        let rows = try [
            row(1, due: "2026-09-30"), row(2, due: day.description), row(3), row(4, status: "/"), row(5, status: "-"),
            row(6, status: "x"),
        ]
        let value = try TodayPresentation(
            day: summary(events: 3), groups: TaskGroups(rows: rows, on: day, isToday: true),
            goals: daily + [weekly], goalStatuses: [daily[0].key: status], today: day,
            locale: Locale(identifier: language), calendar: calendar)
        #expect(value.counter(for: .goals) == "1/3")
        #expect(value.counter(for: .tasks) == "4")
        #expect(value.counter(for: .events) == "3")
        #expect(value.counter(for: .calendar) == nil)
        #expect(value.counter(for: .journal) == nil)
        #expect(value.remainingGoalCount == 2)
        #expect(try make(locale: language).counter(for: .goals) == "0/0")
    }

    @Test func completedOverlayAndHistoricalClosedRowsAreCountedOnce() throws {
        let retained = try row(1, due: "2026-09-30")
        let closed = try row(2, status: "x", due: day.description)
        let cancelled = try row(3, status: "-", due: day.description)
        var groups = TaskGroups(rows: [closed, cancelled], on: day, isToday: false)
        groups.overdue = [retained]
        let value = try TodayPresentation(
            day: summary(), groups: groups, goals: [], goalStatuses: [:], today: day,
            locale: Locale(identifier: "en_US"), calendar: calendar, completedTasks: [closed],
            completedTaskIDs: [retained.id], isCompletedExpanded: true)
        #expect(value.remainingTaskCount == 0)
        #expect(value.carriedOverTasks.isEmpty)
        #expect(value.datedTasks.isEmpty)
        #expect(value.completedTaskRows.map(\.id) == [retained.id, closed.id])
        #expect(value.byline == nil)
    }

    @Test(arguments: ["tr_TR", "en_US"])
    func boxStatePriorityAndSpokenValue(_ language: String) throws {
        let locale = Locale(identifier: language)
        let cases: [(String, String?, TaskBoxState, String, String)] = [
            (" ", nil, .open, "", language == "tr_TR" ? "Açık" : "Open"),
            ("/", "🔼", .inProgress, "!", language == "tr_TR" ? "Devam, Orta öncelik" : "In progress, Medium priority"),
            ("x", "⏫", .done, "!!", language == "tr_TR" ? "Tamamlandı, Yüksek öncelik" : "Completed, High priority"),
            (" ", "🔽", .open, "", language == "tr_TR" ? "Açık, Düşük öncelik" : "Open, Low priority"),
        ]
        for (status, priority, state, mark, spoken) in cases {
            let box = try TaskBoxPresentation(row: row(1, status: status, priority: priority))
            #expect(box.state == state)
            #expect(box.priorityMark == mark)
            #expect(box.accessibilityValue(locale: locale) == spoken)
        }
        #expect(try TaskBoxPresentation(row: row(1), isCompleted: true).state == .done)
    }
}
