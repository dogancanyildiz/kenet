import Foundation
import Testing
import VaultFormat

@testable import Kenet

/// Short dates the day pages and the Günlük column draw (drawings: "‹ 17 Eyl", "20 Eylül Pazar").
struct DayLabelTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        return value
    }

    @Test func backLabelIsDayAndShortMonth() {
        let day = CalendarDate("2026-09-17")!
        let today = CalendarDate("2026-11-11")!
        #expect(
            DayBackLabel.text(for: day, today: today, locale: Locale(identifier: "tr_TR"), calendar: calendar)
                == "17 Eyl")
        #expect(
            DayBackLabel.text(for: day, today: today, locale: Locale(identifier: "en_US"), calendar: calendar)
                == "Sep 17")
    }

    @Test func backLabelNamesAnotherYear() {
        let day = CalendarDate("2025-09-17")!
        let today = CalendarDate("2026-11-11")!
        let text = DayBackLabel.text(
            for: day, today: today, locale: Locale(identifier: "tr_TR"), calendar: calendar)
        #expect(text.contains("2025"))
        #expect(text.hasPrefix("17 Eyl"))
    }

    @Test func columnTitleIsTheFullDate() {
        let day = CalendarDate("2026-09-20")!
        #expect(DayRow.columnTitle(day, today: day, locale: Locale(identifier: "tr_TR")) == "20 Eylül Pazar")
        #expect(
            DayRow.columnTitle(day, today: CalendarDate("2027-01-02")!, locale: Locale(identifier: "tr_TR"))
                .contains("2026"))
    }
}
