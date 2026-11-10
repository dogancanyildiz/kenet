import Foundation
import SwiftUI
import Testing

@testable import Journal

struct InkDesignComponentTests {
    @Test func glowShouldDrawRespectsContrastAndTransparency() {
        #expect(InkGlowChrome.shouldDraw(contrast: .standard, reduceTransparency: false))
        #expect(!InkGlowChrome.shouldDraw(contrast: .increased, reduceTransparency: false))
        #expect(!InkGlowChrome.shouldDraw(contrast: .standard, reduceTransparency: true))
        #expect(!InkGlowChrome.shouldDraw(contrast: .increased, reduceTransparency: true))
    }

    @Test func weekStripDaysFollowMondayFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2  // Monday
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16))!
        let days = InkWeekStrip.daysInWeek(containing: wednesday, calendar: calendar)
        #expect(days.count == 7)
        #expect(calendar.component(.weekday, from: days[0]) == 2)
        #expect(calendar.component(.day, from: days[0]) == 14)
        #expect(calendar.component(.day, from: days[6]) == 20)
    }

    @Test func weekStripDaysFollowSundayFirstWeekdayAcrossYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1  // Sunday
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let newYear = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let days = InkWeekStrip.daysInWeek(containing: newYear, calendar: calendar)
        #expect(days.count == 7)
        #expect(calendar.component(.weekday, from: days[0]) == 1)
        #expect(calendar.component(.year, from: days[0]) == 2026)
        #expect(calendar.component(.month, from: days[0]) == 12)
        #expect(calendar.component(.day, from: days[0]) == 27)
        #expect(calendar.component(.year, from: days[6]) == 2027)
        #expect(calendar.component(.day, from: days[6]) == 2)
    }

    @Test func weekStripAccessibilityIncludesTodayAndWritten() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let label = InkWeekStrip.accessibilityLabel(
            day: day, written: true, calendar: calendar, locale: Locale(identifier: "tr_TR"),
            isToday: true)
        #expect(label.contains("bugün"))
        #expect(label.contains("yazıldı"))
        #expect(label.contains("14"))
    }

    @Test func weekStripAccessibilityReadsEventCountAfterToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let label = InkWeekStrip.accessibilityLabel(
            day: day, written: true, calendar: calendar, locale: Locale(identifier: "tr_TR"),
            isToday: true, eventCount: 3)
        #expect(label.hasSuffix(", bugün, 3 olay"))
        #expect(!label.contains("yazıldı"))

        let quiet = InkWeekStrip.accessibilityLabel(
            day: day, written: false, calendar: calendar, locale: Locale(identifier: "tr_TR"),
            isToday: false)
        #expect(!quiet.contains(","))
    }

    @Test func summaryLineSpokenPartsKeepCallerFormatting() {
        let parts: [InkSummaryLine.Part] = [
            .text("Bugün"),
            .count(LocalizedStringResource(stringLiteral: "2 olay"), symbol: "calendar"),
            .text("ve"),
            .count(LocalizedStringResource(stringLiteral: "6 görev")),
        ]
        #expect(InkSummaryLine.spokenParts(parts) == ["Bugün", "2 olay", "ve", "6 görev"])
        let glued: [InkSummaryLine.Part] = [
            .count(LocalizedStringResource(stringLiteral: "2 events"), suffix: ","),
            .count(LocalizedStringResource(stringLiteral: "3 goals"), suffix: "."),
        ]
        #expect(InkSummaryLine.spoken(glued) == "2 events, 3 goals.")
    }
}
