import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct CalendarDensityTests {
    private func makeDay(date: CalendarDate, eventCount: Int, hasJournal: Bool) -> DayOverview {
        DayOverview(
            id: "journal/\(date).md", date: date, eventCount: eventCount, journalCount: hasJournal ? 1 : 0,
            preview: hasJournal ? "Günlük yazısı" : nil)
    }

    @Test func scoreAndDensityThresholds() throws {
        let day0 = makeDay(date: CalendarDate("2026-09-01")!, eventCount: 0, hasJournal: false)
        #expect(JournalCalendar.score(for: day0) == 0)
        #expect(JournalCalendar.densityLevel(for: day0) == 0)

        // Threshold 1: either 1 event or journal entry
        let day1Event = makeDay(date: CalendarDate("2026-09-02")!, eventCount: 1, hasJournal: false)
        #expect(JournalCalendar.score(for: day1Event) == 1)
        #expect(JournalCalendar.densityLevel(for: day1Event) == 1)

        let day1JournalOnly = makeDay(date: CalendarDate("2026-09-03")!, eventCount: 0, hasJournal: true)
        #expect(JournalCalendar.score(for: day1JournalOnly) == 1)
        #expect(JournalCalendar.densityLevel(for: day1JournalOnly) == 1)

        // Threshold 2: score 2 (lower bound for level 2)
        let day2 = makeDay(date: CalendarDate("2026-09-04")!, eventCount: 2, hasJournal: false)
        #expect(JournalCalendar.score(for: day2) == 2)
        #expect(JournalCalendar.densityLevel(for: day2) == 2)

        let day2WithJournal = makeDay(date: CalendarDate("2026-09-05")!, eventCount: 1, hasJournal: true)
        #expect(JournalCalendar.score(for: day2WithJournal) == 2)
        #expect(JournalCalendar.densityLevel(for: day2WithJournal) == 2)

        // Threshold 4: score 4 (upper bound for level 2)
        let day4 = makeDay(date: CalendarDate("2026-09-06")!, eventCount: 4, hasJournal: false)
        #expect(JournalCalendar.score(for: day4) == 4)
        #expect(JournalCalendar.densityLevel(for: day4) == 2)

        let day4WithJournal = makeDay(date: CalendarDate("2026-09-07")!, eventCount: 3, hasJournal: true)
        #expect(JournalCalendar.score(for: day4WithJournal) == 4)
        #expect(JournalCalendar.densityLevel(for: day4WithJournal) == 2)

        // Threshold 5: score 5 (lower bound for level 3)
        let day5 = makeDay(date: CalendarDate("2026-09-08")!, eventCount: 5, hasJournal: false)
        #expect(JournalCalendar.score(for: day5) == 5)
        #expect(JournalCalendar.densityLevel(for: day5) == 3)

        let day5WithJournal = makeDay(date: CalendarDate("2026-09-09")!, eventCount: 4, hasJournal: true)
        #expect(JournalCalendar.score(for: day5WithJournal) == 5)
        #expect(JournalCalendar.densityLevel(for: day5WithJournal) == 3)

        // Score 6+ (level 3)
        let day6 = makeDay(date: CalendarDate("2026-09-10")!, eventCount: 6, hasJournal: false)
        #expect(JournalCalendar.score(for: day6) == 6)
        #expect(JournalCalendar.densityLevel(for: day6) == 3)
    }

    @Test func monthTransitionPreservesMonthIsolation() throws {
        let sepDay = makeDay(date: CalendarDate("2026-09-15")!, eventCount: 3, hasJournal: true)  // score 4 -> level 2
        let octDay = makeDay(date: CalendarDate("2026-10-15")!, eventCount: 1, hasJournal: false)  // score 1 -> level 1
        let novDay = makeDay(date: CalendarDate("2026-11-01")!, eventCount: 5, hasJournal: false)  // score 5 -> level 3
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
}
