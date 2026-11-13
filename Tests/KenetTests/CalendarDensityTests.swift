import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Kenet

@MainActor struct CalendarDensityTests {
    private func makeDay(
        date: CalendarDate, eventCount: Int, taskCount: Int = 0, hasJournal: Bool
    ) -> DayOverview {
        DayOverview(
            id: "journal/\(date).md", date: date, eventCount: eventCount, journalCount: hasJournal ? 1 : 0,
            preview: hasJournal ? "Günlük yazısı" : nil, taskCount: taskCount)
    }

    @Test func scoreAndDensityThresholds() throws {
        let day0 = makeDay(date: CalendarDate("2026-09-01")!, eventCount: 0, hasJournal: false)
        #expect(JournalCalendar.score(for: day0) == 0)
        #expect(JournalCalendar.densityLevel(for: day0) == 0)

        // Level 1: 1–2 (event + task count, or journal-only = 1)
        let day1Event = makeDay(date: CalendarDate("2026-09-02")!, eventCount: 1, hasJournal: false)
        #expect(JournalCalendar.score(for: day1Event) == 1)
        #expect(JournalCalendar.densityLevel(for: day1Event) == 1)

        let day1JournalOnly = makeDay(date: CalendarDate("2026-09-03")!, eventCount: 0, hasJournal: true)
        #expect(JournalCalendar.score(for: day1JournalOnly) == 1)
        #expect(JournalCalendar.densityLevel(for: day1JournalOnly) == 1)

        let day2 = makeDay(date: CalendarDate("2026-09-04")!, eventCount: 1, taskCount: 1, hasJournal: false)
        #expect(JournalCalendar.score(for: day2) == 2)
        #expect(JournalCalendar.densityLevel(for: day2) == 1)

        // Level 2: 3–5
        let day3 = makeDay(date: CalendarDate("2026-09-05")!, eventCount: 2, taskCount: 1, hasJournal: true)
        #expect(JournalCalendar.score(for: day3) == 3)
        #expect(JournalCalendar.densityLevel(for: day3) == 2)

        let day5 = makeDay(date: CalendarDate("2026-09-06")!, eventCount: 3, taskCount: 2, hasJournal: false)
        #expect(JournalCalendar.score(for: day5) == 5)
        #expect(JournalCalendar.densityLevel(for: day5) == 2)

        // Level 3: 6+
        let day6 = makeDay(date: CalendarDate("2026-09-08")!, eventCount: 4, taskCount: 2, hasJournal: false)
        #expect(JournalCalendar.score(for: day6) == 6)
        #expect(JournalCalendar.densityLevel(for: day6) == 3)

        let day8 = makeDay(date: CalendarDate("2026-09-10")!, eventCount: 6, taskCount: 2, hasJournal: true)
        #expect(JournalCalendar.score(for: day8) == 8)
        #expect(JournalCalendar.densityLevel(for: day8) == 3)
    }

    @Test func monthTransitionPreservesMonthIsolation() throws {
        // sepDay: score 4 -> level 2; octDay: score 1 -> level 1
        let sepDay = makeDay(date: CalendarDate("2026-09-15")!, eventCount: 3, taskCount: 1, hasJournal: true)
        let octDay = makeDay(date: CalendarDate("2026-10-15")!, eventCount: 1, hasJournal: false)
        let novDay = makeDay(date: CalendarDate("2026-11-01")!, eventCount: 6, hasJournal: false)  // score 6 -> level 3
        let days = [sepDay, octDay, novDay]

        // September calendar
        let calSep = JournalCalendar(month: CalendarDate("2026-09-01")!, days: days)
        #expect(calSep.level(for: sepDay.date) == 2)
        #expect(calSep.level(for: octDay.date) == 0)
        #expect(calSep.level(for: novDay.date) == 0)
        #expect(calSep.markedDays.contains(sepDay.date))
        #expect(!calSep.markedDays.contains(octDay.date))
        #expect(!calSep.markedDays.contains(novDay.date))

        // Navigate to October
        let octMonth = calSep.adjacentMonth(1)
        #expect(octMonth.description == "2026-10-01")
        let calOct = JournalCalendar(month: octMonth, days: days)
        #expect(calOct.level(for: octDay.date) == 1)
        #expect(calOct.level(for: sepDay.date) == 0)
        #expect(calOct.level(for: novDay.date) == 0)
        #expect(calOct.markedDays.contains(octDay.date))
        #expect(!calOct.markedDays.contains(sepDay.date))

        // Navigate to November
        let novMonth = calOct.adjacentMonth(1)
        #expect(novMonth.description == "2026-11-01")
        let calNov = JournalCalendar(month: novMonth, days: days)
        #expect(calNov.level(for: novDay.date) == 3)
        #expect(calNov.level(for: octDay.date) == 0)
        #expect(calNov.level(for: sepDay.date) == 0)
        #expect(calNov.markedDays.contains(novDay.date))
        #expect(!calNov.markedDays.contains(octDay.date))
    }

    @Test func voiceOverAccessibilityValueSpeaksLevel() {
        #expect(
            DaysCalendarDayMark.accessibilityValueText(
                level: 0, isToday: false, isSelected: false
            ) == "")
        #expect(
            DaysCalendarDayMark.accessibilityValueText(
                level: 1, isToday: false, isSelected: false
            ) == String(localized: "Yoğunluk \(1) / 3"))
        #expect(
            DaysCalendarDayMark.accessibilityValueText(
                level: 2, isToday: true, isSelected: false
            ) == "\(String(localized: "Bugün")), \(String(localized: "Yoğunluk \(2) / 3"))")
        #expect(
            DaysCalendarDayMark.accessibilityValueText(
                level: 3, isToday: false, isSelected: true
            ) == "\(String(localized: "Yoğunluk \(3) / 3")), \(String(localized: "Seçili"))")
        #expect(
            DaysCalendarDayMark.accessibilityValueText(
                level: 2, isToday: true, isSelected: true
            )
                == "\(String(localized: "Bugün")), \(String(localized: "Yoğunluk \(2) / 3")), \(String(localized: "Seçili"))"
        )
    }

    @Test func densityDotsNeverOverflowCellWidth() {
        #expect(DaysCalendarMarkLayout.dotsWidth(for: 0) == 0)
        #expect(DaysCalendarMarkLayout.dotsWidth(for: 1) == 4)
        #expect(DaysCalendarMarkLayout.dotsWidth(for: 2) == 10)
        #expect(DaysCalendarMarkLayout.dotsWidth(for: 3) == 16)
        #expect(DaysCalendarMarkLayout.dotsWidth(for: 4) == 16)

        let typicalCellWidth: CGFloat = 45
        #expect(DaysCalendarMarkLayout.dotsWidth(for: 3) < typicalCellWidth)
    }

    @Test func dayScheduleSortsTimedChronologicallyAndPlacesUntimedAtEnd() throws {
        func parseTime(_ raw: String) -> EventTime? {
            RawDocument(bytes: Array("## Events\n- \(raw) item".utf8)).bodyLines.events.first?.time
        }
        func makeEvent(_ id: Int, _ rawTime: String?, _ text: String, line: Int) -> EventRow {
            EventRow(
                id: id, time: rawTime.flatMap(parseTime),
                text: LinkedText(spans: [.init(text: text, destination: nil)]),
                sourceLine: line, sourceEnd: line + 1, sourceText: text, sourceIdentifier: nil)
        }
        let lateEvent = makeEvent(0, "14:30", "Öğleden sonra", line: 2)
        let untimedEvent1 = makeEvent(1, nil, "Saatsiz olay 1", line: 3)
        let earlyEvent = makeEvent(2, "09:15", "Sabah kahvesi", line: 4)
        let tieEvent = makeEvent(3, "14:30", "İkinci 14:30", line: 5)
        let untimedEvent2 = makeEvent(4, nil, "Saatsiz olay 2", line: 6)

        let timedEntry = DayScheduleEntry(
            id: "task-timed", time: parseTime("11:00"), fileOrder: 10,
            kind: .event(makeEvent(5, "11:00", "11:00 Eczaneye uğra", line: 10)))
        let untimedEntry = DayScheduleEntry(
            id: "task-untimed", time: nil, fileOrder: 11,
            kind: .event(makeEvent(6, nil, "Market listesi", line: 11)))

        let base = DaySchedulePresentation(
            events: [lateEvent, untimedEvent1, earlyEvent, tieEvent, untimedEvent2],
            tasks: []
        )
        let schedule = DaySchedulePresentation(
            entries: base.timed + base.untimed + [timedEntry, untimedEntry]
        )

        #expect(
            schedule.timed.map(\.id) == [
                "event-2-4",
                "task-timed",
                "event-0-2",
                "event-3-5",
            ])
        #expect(
            schedule.untimed.map(\.id) == [
                "event-1-3",
                "event-4-6",
                "task-untimed",
            ])
        #expect(schedule.allOrdered.suffix(3).map(\.id) == schedule.untimed.map(\.id))
        #expect(DaySchedulePresentation.extractLeadingTime(from: "11:00 Eczaneye uğra")?.raw == "11:00")
        #expect(DaySchedulePresentation.extractLeadingTime(from: "Market listesi") == nil)
    }

    /// Real task rows: the day file's tasks take their place among the events by line, so the
    /// "Saatsiz" group is the file's order; a task from another file comes after them.
    @Test func dayScheduleKeepsTheFileOrderOfRealTaskRows() throws {
        let file = "journal/2026-10-01.md"
        func task(_ line: Int, _ text: String, in path: String = file) throws -> TaskRow {
            let fields: [String: Any] = [
                "file": path, "ordinal": line, "kind": "task", "firstLine": line + 1, "lastLine": line + 1,
                "text": text, "section": "Tasks", "rawStatus": " ", "ownsIdentifier": false,
            ]
            let block = try JSONDecoder().decode(
                IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
            return TaskRow(row: block, links: [])
        }
        func event(_ id: Int, _ text: String, line: Int) -> EventRow {
            EventRow(
                id: id, time: nil, text: LinkedText(spans: [.init(text: text, destination: nil)]),
                sourceLine: line, sourceEnd: line + 1, sourceText: text, sourceIdentifier: nil)
        }
        // ## Tasks (lines 1-3), ## Events (lines 5-6).
        let first = try task(1, "Faturayı öde")
        let timed = try task(2, "10:30 Kargoyu al")
        let second = try task(3, "Kitap iade")
        let elsewhere = try task(0, "Başka dosyadan", in: "notes/Plan.md")
        let schedule = DaySchedulePresentation(
            events: [event(0, "Saatsiz olay", line: 5), event(1, "Son olay", line: 6)],
            tasks: [elsewhere, second, timed, first], dayFile: file)

        #expect(schedule.timed.map(\.id) == ["task-\(timed.id)"])
        #expect(schedule.timed.first?.time?.raw == "10:30")
        #expect(
            schedule.untimed.map(\.id) == [
                "task-\(first.id)", "task-\(second.id)", "event-0-5", "event-1-6", "task-\(elsewhere.id)",
            ])
    }
}
