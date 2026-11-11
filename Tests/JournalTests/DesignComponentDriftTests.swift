import Foundation
import SwiftUI
import Testing

@testable import Journal

/// Rules behind the second drawing-drift pass on shared components (fark2 O1, M1, P4, P5, D7).
struct DesignComponentDriftTests {
    @Test func completedGoalRingIsAccentNotGray() {
        #expect(GoalRingProgress.completeColor == Color.ink.accent)
        #expect(GoalRingProgress.completeColor != Color.ink.secondaryText)
    }

    /// The weekday name follows the calendar's zone, not the process zone: a calendar far
    /// ahead of UTC still names its own day ("Pzt 14", never "Paz 14").
    @Test func weekStripWeekdayUsesCalendarTimeZone() throws {
        let zones = ["Pacific/Kiritimati", "Pacific/Pago_Pago", "UTC"]
        for zoneID in zones {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zoneID))
            calendar.firstWeekday = 2
            let locale = Locale(identifier: "en_US_POSIX")
            let formatter = InkWeekStrip.makeFormatter(
                template: "EEE", calendar: calendar, locale: locale)
            #expect(formatter.timeZone == calendar.timeZone)
            let monday = try #require(
                calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
            let days = InkWeekStrip.daysInWeek(containing: monday, calendar: calendar)
            let names = days.map { formatter.string(from: $0) }
            #expect(names == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], "\(zoneID)")
        }
    }

    @Test func quickEntryKeepsOneRowOnRegularWidth() {
        #expect(QuickEntryCapsuleLayout.usesTwoRows(layout: .singleRow, isCompactWidth: true))
        #expect(!QuickEntryCapsuleLayout.usesTwoRows(layout: .singleRow, isCompactWidth: false))
        #expect(!QuickEntryCapsuleLayout.usesTwoRows(layout: .stacked, isCompactWidth: true))
        #expect(!QuickEntryCapsuleLayout.usesTwoRows(layout: .stacked, isCompactWidth: false))
    }

    /// Section titles above cards are title3 bold; tab words and labeled menus are subheadline,
    /// never the byline size (drawing: component sheet and Tasks).
    @Test func controlAndSectionTypeSizes() {
        #expect(Font.ink.sectionTitle == Font.system(.title3, design: .default, weight: .bold))
        #expect(InkTabsChrome.pageFont == Font.subheadline)
        #expect(InkLabeledMenuChrome.font == Font.subheadline)
        #expect(InkTabsChrome.pageFont != Font.ink.byline)
        #expect(InkLabeledMenuChrome.font != Font.ink.byline)
    }
}
