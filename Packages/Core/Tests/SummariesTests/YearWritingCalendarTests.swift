import Foundation
import Summaries
import Testing
import VaultFormat
import VaultIndex

struct YearWritingCalendarTests {
    @Test func yearFixturesMatchHandCountedExpectations() throws {
        let fixtures = fixtureDirectory()
        let cases = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtures.appendingPathComponent("summaries/year-writing.json")))
                as? [[String: Any]])
        #expect(cases.count == 6)
        for fixture in cases {
            let year = try #require(fixture["year"] as? Int)
            let today = (fixture["today"] as? String).flatMap { CalendarDate($0) }
            let start = try #require(CalendarDate(year: year, month: 1, day: 1))
            let end = try #require(CalendarDate(year: year, month: 12, day: 31))
            let days = try summaryDays(fixture, from: start, to: end)
            let result = YearWritingCalendar.compute(days: days, year: year, today: today)
            let expected = try #require(fixture["expected"] as? [String: Any])
            #expect(
                try canonical(yearSnapshot(result)) == canonical(expected),
                Comment(rawValue: fixture["id"] as? String ?? ""))
        }
    }

    /// The map's counter is the screen's "Yazılan gün": both read the same rows the same way.
    @Test func writtenDaysMatchTheYearSummary() throws {
        let fixtures = fixtureDirectory()
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: fixtures.appendingPathComponent("vaults/rhythm"))
        for (day, today) in [("2026-10-07", "2026-10-07"), ("2025-03-01", "2026-10-07")] {
            let containing = try #require(CalendarDate(day))
            let now = try #require(CalendarDate(today))
            let range = SummaryPeriod.year.bounds(containing: containing)
            let data = try index.summaryInput(from: range.lowerBound, to: range.upperBound)
            let summary = PeriodSummary.compute(period: .year, containing: containing, data: data, today: now)
            let days = try index.summaryDays(from: range.lowerBound, to: range.upperBound)
            let map = YearWritingCalendar.compute(days: days, year: containing.year, today: now)
            #expect(map.writtenDays == summary.counts.writtenDays)
            #expect(map.measuredEnd == summary.measuredRange.upperBound)
        }
    }

    /// The light day query reads the summary's own rules: a Journal heading writes the day,
    /// a blank Journal or an empty heading or text under another heading does not, and a task alone does not.
    @Test func dayQueryMatchesTheSummaryRows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "2026-02-01": "## Journal\n### Başlık\n",
            "2026-02-02": "## Journal\n   \n",
            "2026-02-03": "## Notlar\nBaşka bölüm.\n",
            "2026-02-04": "## Tasks\n- [ ] görev\n",
            "2026-02-05": "## Events\n- 09:00 kahve\n- 10:00 yürüyüş\n\n## Journal\nBir gün.\n",
            "2026-02-06": "## Journal\n### \n",
        ]
        for (date, body) in files {
            let url = root.appendingPathComponent("journal/\(date).md")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(body.utf8).write(to: url)
        }
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let start = try #require(CalendarDate("2026-02-01"))
        let end = try #require(CalendarDate("2026-02-28"))
        let days = try index.summaryDays(from: start, to: end)
        #expect(days.map(\.date.description) == files.keys.sorted())
        #expect(days.map(\.events) == [0, 0, 0, 0, 2, 0])
        #expect(days.map(\.hasJournal) == [true, false, false, false, true, false])
        let input = try index.summaryInput(from: start, to: end).days
        #expect(days.map(\.events) == input.map(\.events))
        #expect(days.map(\.hasJournal) == input.map(\.hasJournal))
        #expect(YearWritingCalendar.compute(days: days, year: 2026).writtenDays == 2)
    }

    @Test func dayLooksUpMeasuredDaysOnly() throws {
        let rows: [SummaryInput.Day] = [
            .init(date: CalendarDate("2026-03-04")!, events: 0, hasJournal: true),
            .init(date: CalendarDate("2026-03-05")!, events: 1, hasJournal: true),
        ]
        let map = YearWritingCalendar.compute(days: rows, year: 2026, today: CalendarDate("2026-03-05"))
        #expect(map.day(CalendarDate("2026-03-04")!) == .journal)
        #expect(map.day(CalendarDate("2026-03-05")!) == .events)
        #expect(map.day(CalendarDate("2026-03-03")!) == .unwritten)
        #expect(map.day(CalendarDate("2026-03-06")!) == nil)
        #expect(map.day(CalendarDate("2025-03-04")!) == nil)
    }
}

/// Rows of the fixture's vault over the range, or the fixture's own `days` rows.
func summaryDays(_ fixture: [String: Any], from: CalendarDate, to: CalendarDate) throws -> [SummaryInput.Day] {
    if let vault = fixture["vault"] as? String {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: fixtureDirectory().appendingPathComponent("vaults/" + vault))
        let days = try index.summaryDays(from: from, to: to)
        // The light day query is the summary's own day rows.
        let input = try index.summaryInput(from: from, to: to).days
        #expect(days.map(\.date) == input.map(\.date))
        #expect(days.map(\.events) == input.map(\.events))
        #expect(days.map(\.hasJournal) == input.map(\.hasJournal))
        return days
    }
    let rows = try #require(fixture["days"] as? [[String: Any]])
    return try rows.map { row in
        SummaryInput.Day(
            date: try #require((row["date"] as? String).flatMap { CalendarDate($0) }),
            events: try #require(row["events"] as? Int), hasJournal: try #require(row["hasJournal"] as? Bool))
    }
}

private func yearSnapshot(_ value: YearWritingCalendar) -> [String: Any] {
    var events: [String] = []
    var journal: [String] = []
    for month in value.months {
        for (offset, day) in month.days.enumerated() {
            let date = CalendarDate(year: value.year, month: month.month, day: offset + 1)!.description
            switch day {
            case .events: events.append(date)
            case .journal: journal.append(date)
            case .unwritten: break
            }
        }
    }
    return [
        "eventDays": events, "journalDays": journal,
        "measuredEnd": value.measuredEnd?.description as Any? ?? NSNull(),
        "monthDays": value.months.map(\.days.count), "monthWritten": value.months.map(\.writtenDays),
        "writtenDays": value.writtenDays,
    ]
}
