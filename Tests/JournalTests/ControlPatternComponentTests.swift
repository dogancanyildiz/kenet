import Foundation
import SwiftUI
import Testing

@testable import Journal

/// Pure decisions behind the control-pattern components. That the views really route through
/// them is measured on the drawn and mounted views: `ControlChromeRenderTests` (colors),
/// `ControlAccessibilityHostedTests` (names, values, layout), `ShellSheetKindHostedTests` (sheets).
@MainActor struct ControlPatternComponentTests {
    // MARK: - Manşet row icons

    @Test func headerActionColorFollowsRoleAndActiveState() {
        #expect(InkHeaderActionChrome.token(role: .utility) == .secondaryText)
        #expect(InkHeaderActionChrome.token(role: .primary) == .accent)
        // A non-default sort / filter turns the utility icon accent.
        #expect(InkHeaderActionChrome.token(role: .utility, isActive: true) == .accent)
        #expect(InkHeaderActionChrome.token(role: .primary, isActive: true) == .accent)
        // Disabled never keeps the action color.
        #expect(InkHeaderActionChrome.token(role: .primary, isEnabled: false) == .secondaryText)
        #expect(
            InkHeaderActionChrome.token(role: .utility, isActive: true, isEnabled: false)
                == .secondaryText)
    }

    @Test func headerHoldsAtMostThreeIcons() {
        #expect(InkHeaderActionChrome.maximumCount == 3)
        #expect(InkHeaderActionChrome.fits(count: 0))
        #expect(InkHeaderActionChrome.fits(count: 3))
        #expect(!InkHeaderActionChrome.fits(count: 4))
    }

    @Test func headerIconsMoveAboveTheHeadlineAtAccessibilitySizes() {
        #expect(InkPageHeaderLayout.resolve(dynamicTypeSize: .large) == .inline)
        #expect(InkPageHeaderLayout.resolve(dynamicTypeSize: .xxxLarge) == .inline)
        #expect(InkPageHeaderLayout.resolve(dynamicTypeSize: .accessibility1) == .stacked)
        #expect(InkPageHeaderLayout.resolve(dynamicTypeSize: .accessibility5) == .stacked)
    }

    @Test func headerStyleDefaultsToUtility() {
        let style = InkHeaderButtonStyle()
        #expect(style.role == .utility)
        #expect(!style.isActive)
    }

    @Test func pressedHeaderIconUsesTextToken() {
        #expect(InkHeaderActionChrome.token(role: .utility, isPressed: true) == .text)
        #expect(InkHeaderActionChrome.token(role: .primary, isActive: true, isPressed: true) == .text)
        #expect(InkHeaderActionChrome.token(role: .primary, isEnabled: false, isPressed: true) == .secondaryText)
    }

    // MARK: - Tabs and labeled menu

    @Test func tabsAreForTwoOrThreeOptions() {
        #expect(InkTabsChrome.maximumCount == 3)
        #expect(!InkTabsChrome.fits(count: 1))
        #expect(InkTabsChrome.fits(count: 2))
        #expect(InkTabsChrome.fits(count: 3))
        #expect(!InkTabsChrome.fits(count: 4))
        // The menu takes over exactly where tabs stop.
        #expect(InkLabeledMenuChrome.minimumCount == InkTabsChrome.maximumCount + 1)
    }

    @Test func tabWordColorsFollowSelection() {
        #expect(InkTabsChrome.token(isSelected: true) == .text)
        #expect(InkTabsChrome.token(isSelected: false) == .secondaryText)
        #expect(InkTabsChrome.underlineToken(isSelected: true) == .accent)
        #expect(InkTabsChrome.underlineToken(isSelected: false) == nil)
    }

    @Test func tabItemsKeepValueAndIdentifier() {
        let item = InkTabItem("Hafta", value: 1, identifier: "tab.summaries.week")
        #expect(item.value == 1)
        #expect(item.id == 1)
        #expect(item.identifier == "tab.summaries.week")
        #expect(InkTabItem(verbatim: "Ay", value: 2).identifier == nil)
    }

    @Test func labeledMenuFindsTheSelectedOptionAcrossSections() {
        let sections = [
            [InkMenuOption(verbatim: "Gün", value: 1), InkMenuOption(verbatim: "Hafta", value: 2)],
            [InkMenuOption(verbatim: "Yıl", value: 3, systemImage: "calendar")],
        ]
        #expect(InkLabeledMenuChrome.selected(2, in: sections)?.value == 2)
        #expect(InkLabeledMenuChrome.selected(3, in: sections)?.systemImage == "calendar")
        #expect(InkLabeledMenuChrome.selected(9, in: sections) == nil)
        #expect(InkLabeledMenuChrome.selected(1, in: [[InkMenuOption<Int>]]()) == nil)
    }

    // MARK: - Filter field

    @Test func filterFieldBorderAndClearButton() {
        #expect(InkFilterFieldChrome.borderToken(isFocused: true) == .accent)
        #expect(InkFilterFieldChrome.borderToken(isFocused: false) == .control)
        #expect(!InkFilterFieldChrome.showsClear(text: ""))
        #expect(InkFilterFieldChrome.showsClear(text: "a"))
        #expect(InkFilterFieldChrome.showsClear(text: " "))
    }

    // MARK: - Sheet

    @Test func sheetConfirmIsEnabledOnlyWhenAllowedAndIdle() {
        #expect(InkSheetChrome.isConfirmEnabled(isEnabled: true, isBusy: false))
        #expect(!InkSheetChrome.isConfirmEnabled(isEnabled: false, isBusy: false))
        #expect(!InkSheetChrome.isConfirmEnabled(isEnabled: true, isBusy: true))
        #expect(!InkSheetChrome.isConfirmEnabled(isEnabled: false, isBusy: true))
        #expect(InkSheetChrome.showsProgress(isBusy: true))
        #expect(!InkSheetChrome.showsProgress(isBusy: false))
    }

    @Test func sheetButtonColorsAndWeights() {
        #expect(InkSheetChrome.token(for: .cancel) == .secondaryText)
        #expect(InkSheetChrome.token(for: .confirm) == .accent)
        #expect(InkSheetChrome.token(for: .close) == .accent)
        #expect(InkSheetChrome.token(for: .confirm, isEnabled: false) == .secondaryText)
        #expect(InkSheetChrome.isEmphasized(.confirm))
        #expect(!InkSheetChrome.isEmphasized(.cancel))
        #expect(!InkSheetChrome.isEmphasized(.close))
    }

    @Test func sheetWordsComeFromOnePlaceAndExistInTheCatalog() {
        #expect(InkSheetChrome.cancelKey == "Vazgeç")
        #expect(InkSheetChrome.closeKey == "Kapat")
        #expect(InkSheetConfirmation.save.catalogKey == "Kaydet")
        #expect(InkSheetConfirmation.create.catalogKey == "Oluştur")
        #expect(InkSheetConfirmation.move.catalogKey == "Taşı")
        let keys = [
            InkSheetChrome.cancelKey, InkSheetChrome.closeKey, InkSheetConfirmation.save.catalogKey,
            InkSheetConfirmation.create.catalogKey, InkSheetConfirmation.move.catalogKey, "Temizle",
            "Seçmek için çift dokun", "Ara",
        ]
        for key in keys {
            for language in ["tr", "en"] {
                #expect(CatalogLookup.hasTranslation(key, language: language), "\(key) has no \(language) entry")
            }
        }
    }

    @Test func macSheetIdealSizePreventsCollapsedBody() {
        // Audit finding 1: empty entity edit sheet was ~133 pt tall with a ~0 pt scroll area.
        #expect(InkSheetChrome.macMinHeight > 133)
        #expect(InkSheetChrome.macContentFits(minHeight: InkSheetChrome.macMinHeight))
        #expect(!InkSheetChrome.macContentFits(minHeight: 133))
        #expect(InkSheetChrome.macMinWidth >= 480)
        #expect(InkSheetChrome.macIdealHeight >= InkSheetChrome.macMinHeight)
    }
}
