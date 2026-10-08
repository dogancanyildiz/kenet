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
        // Above the old 18 pt LazyVGrid row height on `dev`.
        #expect(phone >= 18)
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

    @Test func heatmapTapTargetsFitRowAndColumnPitch() {
        for width: CGFloat in [390, 320] {
            for accessibility in [false, true] {
                let weeks = GoalHeatmapMetrics.weekCount(isAccessibilitySize: accessibility)
                let size = GoalHeatmapMetrics.cellSize(availableWidth: width, weekCount: weeks)
                let tap = GoalHeatmapMetrics.tapSize(cellSize: size)
                let step = GoalHeatmapMetrics.step(cellSize: size)
                let rowSpacing = GoalHeatmapMetrics.rowSpacing(cellSize: size)
                #expect(rowSpacing >= 0, "rowSpacing must not pull rows over each other")
                #expect(
                    tap <= step + rowSpacing,
                    "tap height \(tap) > row pitch \(step + rowSpacing) (w=\(width), ax=\(accessibility))")
                #expect(
                    tap <= step,
                    "tap width \(tap) > column step \(step) (w=\(width), ax=\(accessibility))")
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

    @Test func buttonStylesEnforceMinimumHeightConstant() throws {
        #expect(InkButtonChrome.minimumHeight == 44)
        #expect(InkButtonChrome.minimumHeight == TapTarget.minimumLength)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("App/Design/Components/InkButtonStyles.swift"),
            encoding: .utf8)
        for style in ["InkPrimaryButtonStyle", "InkTextButtonStyle", "InkDestructiveButtonStyle"] {
            let parts = source.components(separatedBy: "struct \(style)")
            #expect(parts.count > 1, "\(style) missing")
            let body = parts[1].components(separatedBy: "struct ").first ?? parts[1]
            #expect(
                body.contains("InkButtonChrome.minimumHeight"),
                "\(style) must use InkButtonChrome.minimumHeight")
            #expect(body.contains(".contentShape("), "\(style) must set contentShape for hit testing")
        }
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

    @Test func goalFieldEditorValidatesInput() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("App/Screens/Goals/GoalFieldEditor.swift"),
            encoding: .utf8)
        #expect(source.contains("isConfirmEnabled: model.canEdit && !isSaved && isValid"))
        #expect(source.contains("private var isValid: Bool"))
    }
}
