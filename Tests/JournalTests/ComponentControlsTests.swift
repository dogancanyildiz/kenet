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
}
