import Foundation
import SwiftUI
import Testing

@testable import Journal

/// Shell chrome rules from the Şafak drawing pass: glow scroll, day ring label, week strip cells.
struct ShellChromeTests {
    @Test func glowFollowsScrollFromRest() {
        // At rest the offset is minus the top inset: no shift.
        #expect(InkGlowChrome.scrollShift(offset: -120, topInset: 120) == 0)
        #expect(InkGlowChrome.scrollShift(offset: 80, topInset: 120) == 200)
        // Pull-down moves the glow down with the content.
        #expect(InkGlowChrome.scrollShift(offset: -150, topInset: 120) == -30)
        // Far down the glow is off screen; the shift stops growing.
        #expect(
            InkGlowChrome.scrollShift(offset: 5000, topInset: 0) == InkGlowChrome.maximumTrackedOffset)
    }

    @Test func dayRingShowsCompletedPercent() {
        #expect(DayRingLabel.percent(0) == 0)
        #expect(DayRingLabel.percent(2.0 / 3.0) == 67)
        #expect(DayRingLabel.percent(1) == 100)
        #expect(DayRingLabel.percent(1.4) == 100)
        #expect(DayRingLabel.percent(-0.2) == 0)
    }

    @Test func weekStripCellStyles() {
        #expect(InkWeekStripChrome.CellStyle.resolve(selected: true, isToday: true) == .framed)
        #expect(InkWeekStripChrome.CellStyle.resolve(selected: true, isToday: false) == .filled)
        #expect(InkWeekStripChrome.CellStyle.resolve(selected: false, isToday: true) == .plain)
        #expect(InkWeekStripChrome.CellStyle.resolve(selected: false, isToday: false) == .plain)
    }

    @Test func headerBackPreferenceIsSticky() {
        var value = false
        InkHeaderBackShownKey.reduce(value: &value) { true }
        InkHeaderBackShownKey.reduce(value: &value) { false }
        #expect(value)
    }
}
