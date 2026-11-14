import Foundation
import SwiftUI
import Testing

@testable import Kenet

struct InkDesignComponentTests {
    @Test func glowShouldDrawRespectsContrastAndTransparency() {
        #expect(InkGlowChrome.shouldDraw(contrast: .standard, reduceTransparency: false))
        #expect(!InkGlowChrome.shouldDraw(contrast: .increased, reduceTransparency: false))
        #expect(!InkGlowChrome.shouldDraw(contrast: .standard, reduceTransparency: true))
        #expect(!InkGlowChrome.shouldDraw(contrast: .increased, reduceTransparency: true))
    }

    /// The manşet title tries the full day name, then the week strip's short one; VoiceOver's
    /// name stays the full one.
    @Test(arguments: [
        ("tr_TR", 19, "Cumartesi", "Cmt"), ("tr_TR", 16, "Çarşamba", "Çar"), ("tr_TR", 17, "Perşembe", "Per"),
        ("en_US", 16, "Wednesday", "Wed"), ("en_US", 19, "Saturday", "Sat"),
    ])
    func dayHeaderTitleNamesShortenLikeTheWeekStrip(
        localeID: String, day: Int, full: String, short: String
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        let locale = Locale(identifier: localeID)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 9))!
        let names = InkDayHeaderTitle.names(for: date, calendar: calendar, locale: locale)
        #expect(names.full == full)
        #expect(names.drawn == [full, short])
        let stripName = InkWeekStrip.makeFormatter(template: "EEE", calendar: calendar, locale: locale)
            .string(from: date)
        #expect(names.drawn.last == stripName)
    }

    /// Large text never keeps the phone manşet on one row; the iPad page and the collapsed header do.
    @Test func dayHeaderLayoutFollowsTextSizeAndWidth() {
        for size in [DynamicTypeSize.xSmall, .large, .xxxLarge] {
            #expect(InkDayHeaderLayout.resolve(compact: false, dynamicTypeSize: size, isWide: false) == .fitted)
            #expect(InkDayHeaderLayout.resolve(compact: false, dynamicTypeSize: size, isWide: true) == .fitted)
        }
        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            #expect(InkDayHeaderLayout.resolve(compact: false, dynamicTypeSize: size, isWide: false) == .stacked)
            #expect(InkDayHeaderLayout.resolve(compact: false, dynamicTypeSize: size, isWide: true) == .singleRow)
        }
        #expect(InkDayHeaderLayout.resolve(compact: true, dynamicTypeSize: .large, isWide: false) == .singleRow)
        #expect(
            InkDayHeaderLayout.resolve(compact: true, dynamicTypeSize: .accessibility5, isWide: false) == .singleRow)
        #expect(InkDayHeaderLayout.largestActionSize == .accessibility2)
    }

    /// A one-row Today title tries shorter dates in order and offers a repeated form once.
    @Test func compactTitleFallbacksRunWidestFirstWithoutRepeats() {
        #expect(
            TodayCompactTitle.distinct(["19 Eyl Cumartesi", "19 Eyl", "19"]) == ["19 Eyl Cumartesi", "19 Eyl", "19"])
        #expect(TodayCompactTitle.distinct(["19 Eyl", "19 Eyl", "19"]) == ["19 Eyl", "19"])
        #expect(TodayCompactTitle.distinct(["", "19", "19"]) == ["19"])
    }

    /// The navigation row's middle item stays centered while it clears both ends, then moves
    /// between them, then takes its own row; it never sits under the back item or the icons.
    @Test func navigationRowKeepsTheMiddleItemClearOfItsEnds() {
        let gap = InkNavigationRowArrangement.gap
        // 393 pt phone, default text: back chip 44, month picker 130, two icons 92.
        #expect(InkNavigationRowArrangement.resolve(width: 361, leading: 44, center: 130, trailing: 92) == .centered)
        // Exactly the gap left beside the wider end still centers; one point less does not.
        #expect(
            InkNavigationRowArrangement.resolve(width: 130 + 2 * (92 + gap), leading: 44, center: 130, trailing: 92)
                == .centered)
        #expect(
            InkNavigationRowArrangement.resolve(width: 130 + 2 * (92 + gap) - 1, leading: 44, center: 130, trailing: 92)
                == .between)
        #expect(
            InkNavigationRowArrangement.resolve(width: 44 + 130 + 92 + 2 * gap, leading: 44, center: 130, trailing: 92)
                == .between)
        #expect(
            InkNavigationRowArrangement.resolve(
                width: 44 + 130 + 92 + 2 * gap - 1, leading: 44, center: 130, trailing: 92)
                == .below)
        // No back item (split shell): its gap is not counted.
        #expect(
            InkNavigationRowArrangement.resolve(width: 130 + 92 + gap, leading: 0, center: 130, trailing: 92)
                == .between)
        // No middle item (iPad day page): nothing to move.
        #expect(InkNavigationRowArrangement.resolve(width: 100, leading: 44, center: 0, trailing: 92) == .centered)
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
