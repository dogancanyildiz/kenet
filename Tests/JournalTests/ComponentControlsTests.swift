import Foundation
import Testing

@testable import Journal

struct ComponentControlsTests {
    @Test func heatmapShapeCuesDifferentiateKinds() {
        #expect(HeatmapCellKind.empty.fillHeightFraction == 0)
        #expect(HeatmapCellKind.empty.showsOutline)
        #expect(HeatmapCellKind.partial.fillHeightFraction > 0)
        #expect(HeatmapCellKind.partial.fillHeightFraction < 1)
        #expect(!HeatmapCellKind.partial.showsOutline)
        #expect(HeatmapCellKind.full.fillHeightFraction == 1)
        #expect(HeatmapCellKind.today.fillHeightFraction == 1)
        #expect(HeatmapCellKind.today.showsOutline)
        #expect(!HeatmapCellKind.future.isDrawn)
    }

    @Test func progressFractionClamps() {
        #expect(InkProgressMath.fraction(completed: 0, total: 10) == 0)
        #expect(InkProgressMath.fraction(completed: 5, total: 10) == 0.5)
        #expect(InkProgressMath.fraction(completed: 10, total: 10) == 1)
        #expect(InkProgressMath.fraction(completed: 12, total: 10) == 1)
        #expect(InkProgressMath.fraction(completed: -1, total: 10) == 0)
        #expect(InkProgressMath.fraction(completed: 1, total: 0) == 1)
        #expect(InkProgressMath.counterText(completed: 3, total: 10) == "3/10")
        #expect(InkProgressMath.ratio(done: 1.25, target: 2.5) == 0.5)
        #expect(InkProgressMath.ratio(done: 30, target: 20) == 1)
        #expect(InkProgressMath.fraction(0.5) == 0.5)
        #expect(InkProgressMath.percentText(0.5) == "50%")
    }

    @Test func heatmapCellSizeFitsPhoneWidth() {
        let phone = GoalHeatmapMetrics.cellSize(availableWidth: 390, weekCount: 12)
        #expect(phone >= 24, "12 weeks on 390 pt width need cell ≥ 24 pt, got \(phone)")
        let axWeeks = GoalHeatmapMetrics.weekCount(isAccessibilitySize: true)
        #expect(axWeeks == 6)
        let ax = GoalHeatmapMetrics.cellSize(availableWidth: 390, weekCount: axWeeks)
        #expect(ax >= phone)
        #expect(ax <= GoalHeatmapMetrics.tapHeight)
        #expect(GoalHeatmapMetrics.tapHeight == 44)
    }

    @Test func heatmapContentWidthFitsAvailableWidths() {
        for width: CGFloat in [390, 320] {
            for accessibility in [false, true] {
                let weeks = GoalHeatmapMetrics.weekCount(isAccessibilitySize: accessibility)
                let size = GoalHeatmapMetrics.cellSize(availableWidth: width, weekCount: weeks)
                let content = GoalHeatmapMetrics.contentWidth(weekCount: weeks, cellSize: size)
                #expect(
                    content <= width,
                    "content \(content) > \(width) (ax=\(accessibility), weeks=\(weeks), cell=\(size))")
                #expect(GoalHeatmapMetrics.contentFits(availableWidth: width, weekCount: weeks))
            }
        }
    }

    @Test func buttonChromeUsesTokensNotOpacityStates() {
        let primary = InkButtonChrome.primary
        #expect(primary.role(isPressed: false, isEnabled: true).background == .accent)
        #expect(primary.role(isPressed: false, isEnabled: true).foreground == .onAccent)
        #expect(primary.role(isPressed: true, isEnabled: true).background == .text)
        #expect(primary.role(isPressed: false, isEnabled: false).background == .well)
        #expect(primary.role(isPressed: false, isEnabled: false).foreground == .secondaryText)

        let text = InkButtonChrome.text
        #expect(text.role(isPressed: false, isEnabled: true).foreground == .accent)
        #expect(text.role(isPressed: true, isEnabled: true).foreground == .text)
        #expect(text.role(isPressed: false, isEnabled: false).foreground == .secondaryText)

        let destructive = InkButtonChrome.destructive
        #expect(destructive.role(isPressed: false, isEnabled: true).foreground == .danger)
        #expect(destructive.role(isPressed: false, isEnabled: false).foreground == .secondaryText)
    }

    @Test func infoBandKindsCarryNonColorMarks() {
        #expect(InfoBandKind.info.markSystemImage == nil)
        #expect(InfoBandKind.warning.markSystemImage != nil)
        #expect(InfoBandKind.error.markSystemImage != nil)
    }

    @Test func quickEntryModesUseCatalogKeys() {
        #expect(QuickEntryMode.event.catalogKey == "Olay")
        #expect(QuickEntryMode.task.catalogKey == "Görev")
    }

    @Test func largeNumberBaseMatchesDesignTable() {
        #expect(InkSize.largeNumber == 48)
        #expect(InkSize.send == 36)
        #expect(InkSize.modeUnderline == 2)
    }
}
