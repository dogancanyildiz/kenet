import Foundation
import SwiftUI
import Testing

@testable import Journal

/// Third drawing-drift pass on shared components and the Mac sidebar (fark3 Y1, Y8).
struct DesignChipLocaleTests {
    /// Y1: a chip is a `well` capsule with a 1 pt `rule` border (Şafak `.chip`), filled or not.
    @Test func plainChipIsWellWithRuleBorder() {
        #expect(TagChipChrome.fill(isSelected: false, accentSelection: false) == Color.ink.well)
        let border = TagChipChrome.border(isSelected: false, accentSelection: false)
        #expect(border.color == Color.ink.rule)
        #expect(border.width == InkStroke.rule)
        #expect(border.color != Color.ink.control, "the heavy control stroke read as brackets on Mac")
    }

    /// Selection stays visible without color alone: a thicker accent border on `well`.
    @Test func selectedChipKeepsAccentBorder() {
        #expect(TagChipChrome.fill(isSelected: true, accentSelection: false) == Color.ink.well)
        let border = TagChipChrome.border(isSelected: true, accentSelection: false)
        #expect(border.color == Color.ink.accent)
        #expect(border.width == InkStroke.highPriority)
        #expect(TagChipChrome.fill(isSelected: true, accentSelection: true) == Color.ink.accentSoft)
        #expect(TagChipChrome.border(isSelected: true, accentSelection: true).color == Color.clear)
    }

    /// Y8: the ring's VoiceOver value follows the view's locale, not the process language.
    @Test(arguments: [("tr_TR", "Tamamlandı", "Açık"), ("en_US", "Completed", "Open")])
    func goalRingValueFollowsLocale(identifier: String, complete: String, open: String) {
        let locale = Locale(identifier: identifier)
        #expect(
            GoalRing.accessibilityValue(isComplete: true, isBoolean: false, progress: 1, locale: locale) == complete)
        #expect(GoalRing.accessibilityValue(isComplete: false, isBoolean: true, progress: 0, locale: locale) == open)
        #expect(
            GoalRing.accessibilityValue(isComplete: false, isBoolean: false, progress: 0.42, locale: locale) == "42%")
    }

    #if os(macOS)
        /// Y8: the sidebar's quick-entry caption was English in Turkish Mac references.
        @Test(arguments: [("tr_TR", "⌃⌥Space ile her uygulamadan"), ("en_US", "From any app with ⌃⌥Space")])
        func sidebarQuickEntryCaptionFollowsLocale(identifier: String, expected: String) {
            let caption = MacSidebarQuickEntryCard.caption(display: "⌃⌥Space", locale: Locale(identifier: identifier))
            #expect(caption == expected)
        }
    #endif
}
