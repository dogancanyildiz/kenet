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

    private func row(
        _ id: Int, status: String = " ", due: String? = nil, priority: String? = nil,
        done: String? = nil, includeDoneDate: Bool? = nil, file: String? = nil, on date: CalendarDate? = nil
    ) throws -> TaskRow {
        let on = date ?? day
        var fields: [String: Any] = [
            "file": file ?? "journal/\(on).md", "ordinal": id, "kind": "task", "firstLine": id + 1,
            "lastLine": id + 1, "text": "Sample", "section": "Tasks", "rawStatus": status,
            "ownsIdentifier": false,
        ]
        fields["dueDate"] = due
        fields["priority"] = priority
        if let done {
            fields["doneDate"] = done
        } else if status == "x" || status == "X", includeDoneDate != false {
            fields["doneDate"] = on.description
        }
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
        groups: TaskGroups? = nil, completed: [TaskRow] = [], goalStatusesDay: CalendarDate? = nil,
        goalsDefinitions: [GoalDefinition]? = nil, goalStatuses: [String: GoalStatus] = [:]
    ) throws -> TodayPresentation {
        let definitions: [GoalDefinition]
        if let goalsDefinitions {
            definitions = goalsDefinitions
        } else {
            definitions = (0..<goals).map { index in
                GoalDefinition(
                    id: "goal\(index)", key: "goal\(index)", name: "Sample", period: .day, kind: .boolean)!
            }
        }
        return try TodayPresentation(
            day: summary(events: events),
            groups: groups
                ?? TaskGroups(
                    rows: (0..<tasks).map { try row($0) }, on: day, isToday: true),
            goals: definitions, goalStatuses: goalStatuses, goalStatusesDay: goalStatusesDay ?? day,
            today: day, locale: Locale(identifier: locale), calendar: calendar, completedTasks: completed)
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
        #expect(
            value.shortHeadline == (language == "tr_TR" ? "6 Eki Salı" : "Tue, Oct 6"))
        let september = TodayPresentation.carriedOverDate(
            CalendarDate("2026-09-30")!, today: day, locale: locale, calendar: calendar)
        #expect(september == (language == "tr_TR" ? "30 Eyl'den" : "from Sep 30"))
        let longDay = CalendarDate("2026-09-30")!
        #expect(
            TodayPresentation.shortHeadline(longDay, today: day, locale: locale, calendar: calendar)
                == (language == "tr_TR" ? "30 Eyl Çarşamba" : "Wed, Sep 30"))
        let previous = CalendarDate("2025-12-31")!
        let now = CalendarDate("2026-01-02")!
        let past = try TodayPresentation(
            day: summary(date: previous), groups: TaskGroups(rows: [], on: previous, isToday: false),
            goals: [], goalStatuses: [:], goalStatusesDay: previous, today: now, locale: locale,
            calendar: calendar)
        #expect(past.headline == (language == "tr_TR" ? "31 Aralık 2025 Çarşamba" : "Wednesday, December 31, 2025"))
        #expect(
            past.shortHeadline
                == (language == "tr_TR" ? "31 Ara 2025 Çarşamba" : "Wed, Dec 31, 2025"))
        #expect(
            TodayPresentation.carriedOverDate(previous, today: now, locale: locale, calendar: calendar)
                == (language == "tr_TR" ? "31 Ara 2025'ten" : "from Dec 31, 2025"))
    }

    @Test func turkishCarriedOverDateUsesMonthAndYearAblative() throws {
        let locale = Locale(identifier: "tr_TR")
        let english = Locale(identifier: "en_US")
        let yearless: [(String, String, String)] = [
            ("2026-01-05", "5 Oca'tan", "from Jan 5"),
            ("2026-02-05", "5 Şub'tan", "from Feb 5"),
            ("2026-03-03", "3 Mar'tan", "from Mar 3"),
            ("2026-04-05", "5 Nis'dan", "from Apr 5"),
            ("2026-05-05", "5 May'tan", "from May 5"),
            ("2026-06-05", "5 Haz'dan", "from Jun 5"),
            ("2026-07-05", "5 Tem'dan", "from Jul 5"),
            ("2026-08-05", "5 Ağu'tan", "from Aug 5"),
            ("2026-09-30", "30 Eyl'den", "from Sep 30"),
            ("2026-10-05", "5 Eki'den", "from Oct 5"),
            ("2026-11-05", "5 Kas'dan", "from Nov 5"),
            ("2026-12-31", "31 Ara'tan", "from Dec 31"),
        ]
        for (date, turkish, englishText) in yearless {
            let value = CalendarDate(date)!
            #expect(
                TodayPresentation.carriedOverDate(value, today: day, locale: locale, calendar: calendar)
                    == turkish)
            #expect(
                TodayPresentation.carriedOverDate(value, today: day, locale: english, calendar: calendar)
                    == englishText)
        }
        let withYear: [(String, String, String, String)] = [
            ("2000-06-01", "2001-01-01", "1 Haz 2000'den", "from Jun 1, 2000"),
            ("2019-04-05", "2020-01-01", "5 Nis 2019'dan", "from Apr 5, 2019"),
            ("2023-03-03", "2024-01-01", "3 Mar 2023'ten", "from Mar 3, 2023"),
            ("2024-02-29", "2025-01-01", "29 Şub 2024'ten", "from Feb 29, 2024"),
            ("2025-12-31", "2026-01-02", "31 Ara 2025'ten", "from Dec 31, 2025"),
            ("2026-06-05", "2027-01-01", "5 Haz 2026'dan", "from Jun 5, 2026"),
            ("2030-01-05", "2031-01-01", "5 Oca 2030'dan", "from Jan 5, 2030"),
            ("2040-08-05", "2041-01-01", "5 Ağu 2040'tan", "from Aug 5, 2040"),
        ]
        for (date, today, turkish, englishText) in withYear {
            let value = CalendarDate(date)!
            let asOf = CalendarDate(today)!
            #expect(
                TodayPresentation.carriedOverDate(value, today: asOf, locale: locale, calendar: calendar)
                    == turkish)
            #expect(
                TodayPresentation.carriedOverDate(value, today: asOf, locale: english, calendar: calendar)
                    == englishText)
        }
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
            goals: daily + [weekly], goalStatuses: [daily[0].key: status], goalStatusesDay: day, today: day,
            locale: Locale(identifier: language), calendar: calendar)
        #expect(value.counter(for: .goals) == "1/3")
        #expect(value.countedGoalIDs == daily.map(\.id))
        #expect(value.counter(for: .tasks) == "4")
        #expect(value.counter(for: .events) == "3")
        #expect(value.counter(for: .calendar) == nil)
        #expect(value.counter(for: .journal) == nil)
        #expect(value.remainingGoalCount == 2)
        #expect(try make(locale: language).counter(for: .goals) == "0/0")
        #expect(try make(locale: language).countedGoalIDs.isEmpty)
    }

    @Test func completedOverlayAndHistoricalClosedRowsAreCountedOnce() throws {
        let retained = try row(1, due: "2026-09-30")
        let closed = try row(2, status: "x", due: day.description)
        let cancelled = try row(3, status: "-", due: day.description)
        var groups = TaskGroups(rows: [closed, cancelled], on: day, isToday: false)
        groups.overdue = [retained]
        let value = try TodayPresentation(
            day: summary(), groups: groups, goals: [], goalStatuses: [:], goalStatusesDay: day, today: day,
            locale: Locale(identifier: "en_US"), calendar: calendar, completedTasks: [closed],
            completedTaskIDs: [retained.id], isCompletedExpanded: true)
        #expect(value.remainingTaskCount == 0)
        #expect(value.carriedOverTasks.isEmpty)
        #expect(value.datedTasks.isEmpty)
        #expect(value.completedTaskRows.map(\.id) == [retained.id, closed.id])
        #expect(value.taskRows.map(\.id) == [cancelled.id, retained.id, closed.id])
        #expect(value.representedTaskIDs == [retained.id, closed.id, cancelled.id])
        #expect(value.byline == nil)
    }

    @Test func pastDayKeepsEveryClosedRowIncludingFoldedCompleted() throws {
        let past = CalendarDate("2026-10-01")!
        let open = try row(1, due: past.description, on: past)
        let doneLater = try row(2, status: "x", due: past.description, done: "2026-10-03", on: past)
        let cancelled = try row(3, status: "-", due: past.description, on: past)
        let doneSame = try row(4, status: "x", due: past.description, done: past.description, on: past)
        let undatedDone = try row(
            5, status: "x", due: nil, done: "2026-10-04", file: "journal/\(past).md", on: past)
        let doneWithoutDate = try row(
            6, status: "x", due: past.description, includeDoneDate: false, on: past)
        let rows = [open, doneLater, cancelled, doneSame, undatedDone, doneWithoutDate]
        let groups = TaskGroups(rows: rows, on: past, isToday: false)
        #expect(groups.dated.count + groups.created.count == 6)
        var value = try TodayPresentation(
            day: summary(date: past), groups: groups, goals: [], goalStatuses: [:], goalStatusesDay: past,
            today: day, locale: Locale(identifier: "en_US"), calendar: calendar)
        #expect(value.representedTaskIDs == Set(rows.map(\.id)))
        #expect(value.taskRows.map(\.id) == [open.id, cancelled.id])
        #expect(value.completedTaskCount == 4)
        #expect(value.completedDisclosure == "4 tasks completed")
        #expect(value.remainingTaskCount == 1)
        value.isCompletedExpanded = true
        #expect(Set(value.taskRows.map(\.id)) == Set(rows.map(\.id)))
        #expect(value.taskRows.first?.id == open.id)
        #expect(value.taskRows.contains { $0.id == cancelled.id && $0.rawStatus == "-" })
    }

    @Test func goalStatusesForAnotherDayOmitGoalCounts() throws {
        let daily = GoalDefinition(id: "g0", key: "g0", name: "Sample", period: .day, kind: .boolean)!
        let other = CalendarDate("2026-10-05")!
        let status = GoalProgress.compute(
            definition: daily, logs: [GoalLog(day: other, value: .boolean(true))], today: other)
        let mismatched = try TodayPresentation(
            day: summary(), groups: TaskGroups(rows: [], on: day, isToday: true), goals: [daily],
            goalStatuses: [daily.key: status], goalStatusesDay: other, today: day,
            locale: Locale(identifier: "en_US"), calendar: calendar)
        #expect(mismatched.goalCount == 0)
        #expect(mismatched.completedGoalCount == 0)
        #expect(mismatched.remainingGoalCount == 0)
        #expect(mismatched.countedGoalIDs.isEmpty)
        #expect(mismatched.counter(for: .goals) == "0/0")
        let matched = try TodayPresentation(
            day: summary(), groups: TaskGroups(rows: [], on: day, isToday: true), goals: [daily],
            goalStatuses: [
                daily.key: GoalProgress.compute(
                    definition: daily, logs: [GoalLog(day: day, value: .boolean(true))], today: day)
            ], goalStatusesDay: day, today: day, locale: Locale(identifier: "en_US"), calendar: calendar)
        #expect(matched.goalCount == 1)
        #expect(matched.completedGoalCount == 1)
        #expect(matched.countedGoalIDs == [daily.id])
    }

    @Test func unsupportedLocaleFallsBackToAppLocalization() throws {
        let app = try #require(Bundle.preferredLocalizations(from: ["tr", "en"]).first)
        let resolved = PresentationLocalization.resolvedLocale(Locale(identifier: "de_DE"))
        #expect(resolved.identifier == app)
        let german = try make(events: 1, locale: "de_DE")
        let fallback = try make(events: 1, locale: app)
        #expect(german.headline == fallback.headline)
        #expect(german.byline == fallback.byline)
        let carried = TodayPresentation.carriedOverDate(
            CalendarDate("2026-09-30")!, today: day, locale: Locale(identifier: "de_DE"), calendar: calendar)
        let expected = TodayPresentation.carriedOverDate(
            CalendarDate("2026-09-30")!, today: day, locale: Locale(identifier: app), calendar: calendar)
        #expect(carried == expected)
    }

    @Test func supportedLanguageKeepsRegionFormatting() throws {
        #expect(PresentationLocalization.resolvedLocale(Locale(identifier: "en_GB")).identifier == "en_GB")
        let british = try make(events: 1, locale: "en_GB")
        #expect(british.headline == "Tuesday 6 October")
        #expect(british.byline == "1 event")
        let carried = TodayPresentation.carriedOverDate(
            CalendarDate("2026-09-30")!, today: day, locale: Locale(identifier: "en_GB"), calendar: calendar)
        #expect(carried == "from 30 Sep")
    }

    @Test func todayIgnoresClosedRowsFromOtherDays() throws {
        let groups = TaskGroups(rows: [], on: day, isToday: true)
        let closed = [
            try row(1, status: "x", due: "2026-09-01", done: "2026-09-02"),
            try row(2, status: "x", due: "2026-10-05", done: "2026-10-05"),
            try row(3, status: "x", due: day.description, done: day.description),
            try row(4, status: "-", due: "2026-09-01"),
        ]
        let value = try make(locale: "en_US", groups: groups, completed: closed)
        #expect(value.completedTaskCount == 1)
        #expect(value.representedTaskIDs == [closed[2].id])
    }

    @Test(arguments: ["tr_TR", "en_US"])
    func boxStatePriorityAndSpokenValue(_ language: String) throws {
        let locale = Locale(identifier: language)
        let cases: [(String, String?, TaskStatus, String, String)] = [
            (" ", nil, .todo, "", language == "tr_TR" ? "Açık" : "Open"),
            ("/", "🔼", .inProgress, "!", language == "tr_TR" ? "Devam, Orta öncelik" : "In progress, Medium priority"),
            ("x", "⏫", .done, "!!", language == "tr_TR" ? "Tamamlandı, Yüksek öncelik" : "Completed, High priority"),
            ("-", nil, .cancelled, "", language == "tr_TR" ? "İptal" : "Cancelled"),
            (" ", "🔽", .todo, "", language == "tr_TR" ? "Açık, Düşük öncelik" : "Open, Low priority"),
        ]
        for (status, priority, expectedStatus, mark, spoken) in cases {
            let box = try TaskBoxPresentation(row: row(1, status: status, priority: priority))
            #expect(box.state.status == expectedStatus)
            #expect(box.priorityMark == mark)
            #expect(box.accessibilityValue(locale: locale) == spoken)
        }
        #expect(try TaskBoxPresentation(row: row(1), isCompleted: true).state.status == .done)
        #expect(try TaskBoxPresentation(row: row(1, status: "-"), isCompleted: true).state.status == .cancelled)
    }

    @Test func displayRowsPlaceCarriedDisclosureBetweenGroups() throws {
        var groups = TaskGroups(rows: [], on: day, isToday: true)
        groups.overdue = try (0..<5).map { try row($0, due: "2026-09-\(String(format: "%02d", $0 + 1))") }
        groups.dated = [try row(10, due: day.description)]
        groups.created = [try row(11)]
        let done = try (0..<3).map { try row($0 + 100, status: "x") }
        var value = try make(locale: "tr_TR", groups: groups, completed: done)
        let kinds = value.rows.map { row -> String in
            switch row {
            case .task(let task): "t:\(task.id)"
            case .carriedOverDisclosure: "carried"
            case .completedDisclosure: "completed"
            }
        }
        #expect(kinds.prefix(3).allSatisfy { $0.hasPrefix("t:") })
        #expect(kinds[3] == "carried")
        #expect(kinds[4] == "t:\(groups.dated[0].id)")
        #expect(kinds[5] == "t:\(groups.created[0].id)")
        #expect(kinds.last == "completed")
        value.isCarriedOverExpanded = true
        value.isCompletedExpanded = true
        #expect(
            value.rows.allSatisfy {
                if case .carriedOverDisclosure = $0 { return false }
                if case .completedDisclosure = $0 { return false }
                return true
            })
    }

    @Test func duplicateGoalKeysDoNotTrapWhenBuildingStatuses() throws {
        let first = GoalDefinition(
            id: "goals/A.md", key: "dup", name: "One", period: .day, kind: .boolean)!
        let second = GoalDefinition(
            id: "goals/B.md", key: "dup", name: "Two", period: .day, kind: .boolean)!
        let statuses = TodayPresentation.goalStatuses(
            goals: [first, second], logs: [:], day: day)
        #expect(statuses["dup"] != nil)
        let value = try make(
            locale: "tr_TR", goalsDefinitions: [first, second], goalStatuses: statuses)
        #expect(value.goalCount == 2)
    }

    @Test func dayTaskSecondaryExposesDateRecurrencePriorityAndCarried() throws {
        let locale = Locale(identifier: "tr_TR")
        var fields: [String: Any] = [
            "file": "journal/\(day).md", "ordinal": 1, "kind": "task", "firstLine": 2,
            "lastLine": 2, "text": "Sample", "section": "Tasks", "rawStatus": " ",
            "ownsIdentifier": false, "dueDate": "2026-10-06", "priority": "🔽",
            "recurrence": "every week",
        ]
        let block = try JSONDecoder().decode(
            IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        let dated = TaskRow(row: block, links: [])
        let secondary = DayTaskSecondaryPresentation(
            row: dated, isCarriedOver: false, carriedOverLabel: nil,
            today: day, locale: locale, calendar: calendar)
        #expect(secondary.dueLabel != nil)
        #expect(secondary.showsLowPriority)
        #expect(secondary.recurrenceLabel != nil)
        #expect(!secondary.isCarriedOver)

        fields["dueDate"] = "2026-09-14"
        fields["priority"] = "🔼"
        fields["recurrence"] = "not a real recurrence"
        let carriedBlock = try JSONDecoder().decode(
            IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        let carried = TaskRow(row: carriedBlock, links: [])
        let carriedLabel = TodayPresentation.carriedOverDate(
            CalendarDate("2026-09-14")!, today: day, locale: locale, calendar: calendar)
        let carriedFacts = DayTaskSecondaryPresentation(
            row: carried, isCarriedOver: true, carriedOverLabel: carriedLabel,
            today: day, locale: locale, calendar: calendar)
        #expect(carriedFacts.dueLabel == nil)
        #expect(carriedFacts.carriedOverLabel == carriedLabel)
        #expect(carriedFacts.showsUnknownRecurrence)
        #expect(!carriedFacts.showsLowPriority)
    }
}
