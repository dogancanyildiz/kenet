import Foundation
import SwiftUI
import Testing

@testable import Journal

/// Pure decisions behind the control-pattern components, plus source checks that the views
/// really route through those decisions (a helper nobody calls protects nothing).
struct ControlPatternComponentTests {
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

    @Test func headerViewsUseTheChromeDecisions() throws {
        let style = try Self.read("App/Design/Components/InkHeaderButtonStyle.swift")
        #expect(style.contains("InkHeaderActionChrome.token("))
        #expect(style.contains("role: role, isActive: isActive, isEnabled: isEnabled"))
        #expect(style.contains("isPressed: configuration.isPressed"))
        #expect(style.contains("configuration.label"))
        #expect(style.contains(".tapTarget()"), "44 pt target on the style's label")
        #expect(!style.contains("Color.ink."), "the style must not pick a color itself")
        #expect(!style.contains("Capsule"), "frameless")

        let actions = try Self.read("App/Design/Components/InkHeaderAction.swift")
        let action = try Self.section(of: actions, startingAt: "struct InkHeaderAction:")
        #expect(action.contains(".buttonStyle(InkHeaderButtonStyle(role: role, isActive: isActive))"))
        #expect(action.contains(".accessibilityLabel(label)"))
        #expect(!action.contains("Color.ink."))
        let menu = try Self.section(of: actions, startingAt: "struct InkHeaderMenu<")
        #expect(menu.contains("InkHeaderActionChrome.token("))
        #expect(menu.contains("role: role, isActive: isActive, isEnabled: isEnabled"))
        #expect(menu.contains(".tapTarget()"))
        #expect(menu.contains(".accessibilityLabel(label)"))
        #expect(!menu.contains("Color.ink."))

        let header = try Self.read("App/Design/Components/InkPageHeader.swift")
        #expect(header.contains("InkPageHeaderLayout.resolve(dynamicTypeSize: dynamicTypeSize)"))
        #expect(
            header.contains("actions.buttonStyle(InkHeaderButtonStyle())"),
            "plain buttons in the slot (SearchButton) must draw as utility icons")
        let page = try Self.read("App/Design/InkPage.swift")
        for view in ["struct InkPageTitle<", "struct InkPageTitleRow<"] {
            #expect(
                try Self.section(of: page, startingAt: view).contains("InkPageHeader("),
                "\(view) must build on InkPageHeader")
        }
    }

    @Test func headerStyleDefaultsToUtilityAndSearchButtonStaysABareButton() throws {
        let style = InkHeaderButtonStyle()
        #expect(style.role == .utility)
        #expect(!style.isActive)
        // A style or wrapper on SearchButton itself changes how the system toolbar draws it on
        // screens that have not moved yet; the manşet slot supplies the look instead.
        let source = try Self.read("App/Screens/Shared/SearchButton.swift")
        let view = try Self.section(of: source, startingAt: "struct SearchButton: View {")
        #expect(view.contains("Button(\"Ara\", systemImage: \"magnifyingglass\", action: openSearch)"))
        #expect(view.contains(".labelStyle(.iconOnly)"))
        #expect(!view.contains(".buttonStyle("))
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

    @Test func tabsAndQuickEntryShareOneWordDrawing() throws {
        let tabs = try Self.read("App/Design/Components/InkTabs.swift")
        let view = try Self.section(of: tabs, startingAt: "struct InkTabs<")
        #expect(view.contains(".inkTabWord(isSelected: selected, size: .page)"))
        #expect(view.contains("InkTabsChrome.underlineToken(isSelected: selected)"))
        #expect(view.contains(".isSelected"))
        #expect(view.contains(".tapTarget()"))
        let modifier = try Self.section(of: tabs, startingAt: "struct InkTabWordModifier")
        #expect(modifier.contains("InkTabsChrome.token(isSelected: isSelected)"))
        #expect(!modifier.contains("Color.ink."), "word colors come from InkTabsChrome")
        let capsule = try Self.read("App/Design/Components/QuickEntryCapsule.swift")
        #expect(capsule.contains(".inkTabWord(isSelected: selected, size: .compact)"))
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

    @Test func labeledMenuViewUsesSelectionLookupAndSpeaksLabelWithValue() throws {
        let source = try Self.read("App/Design/Components/InkLabeledMenu.swift")
        let view = try Self.section(of: source, startingAt: "struct InkLabeledMenu<")
        #expect(view.contains("InkLabeledMenuChrome.selected(selection, in: sections)"))
        #expect(view.contains(".accessibilityLabel(Text(label))"))
        #expect(view.contains(".accessibilityValue("))
        #expect(view.contains(".accessibilityHint("))
        #expect(view.contains(".tapTarget()"))
        #expect(view.contains(".pickerStyle(.inline)"))
    }

    // MARK: - Filter field

    @Test func filterFieldBorderAndClearButton() {
        #expect(InkFilterFieldChrome.borderToken(isFocused: true) == .accent)
        #expect(InkFilterFieldChrome.borderToken(isFocused: false) == .control)
        #expect(!InkFilterFieldChrome.showsClear(text: ""))
        #expect(InkFilterFieldChrome.showsClear(text: "a"))
        #expect(InkFilterFieldChrome.showsClear(text: " "))
    }

    @Test func filterFieldViewUsesTheChromeDecisions() throws {
        let source = try Self.read("App/Design/Components/InkFilterField.swift")
        let view = try Self.section(of: source, startingAt: "struct InkFilterField:")
        #expect(view.contains("InkFilterFieldChrome.showsClear(text: text)"))
        #expect(view.contains("InkFilterFieldChrome.borderToken(isFocused: focus.wrappedValue)"))
        #expect(view.contains("Color.ink.well"))
        #expect(view.contains(".font(.ink.content)"))
        #expect(view.contains(".font(.ink.placeholder)"))
        #expect(view.contains(".textFieldStyle(.plain)"))
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

    @Test func sheetWordsComeFromOnePlaceAndExistInTheCatalog() throws {
        #expect(InkSheetChrome.cancelKey == "Vazgeç")
        #expect(InkSheetChrome.closeKey == "Kapat")
        #expect(InkSheetConfirmation.save.catalogKey == "Kaydet")
        #expect(InkSheetConfirmation.create.catalogKey == "Oluştur")
        let catalog = try Self.read("App/Resources/Localizable.xcstrings")
        let data = try #require(catalog.data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        let keys = [
            InkSheetChrome.cancelKey, InkSheetChrome.closeKey, InkSheetConfirmation.save.catalogKey,
            InkSheetConfirmation.create.catalogKey, "Temizle", "Seçmek için çift dokun", "Ara",
        ]
        for key in keys {
            #expect(strings[key] != nil, "\(key) missing from the String Catalog")
        }
    }

    @Test func sheetModifierUsesTheChromeDecisions() throws {
        let source = try Self.read("App/Design/Components/InkSheet.swift")
        let modifier = try Self.section(of: source, startingAt: "struct InkSheetModifier:")
        #expect(modifier.contains("InkSheetChrome.isConfirmEnabled("))
        #expect(modifier.contains("isEnabled: isConfirmEnabled, isBusy: isBusy"))
        #expect(modifier.contains("InkSheetChrome.showsProgress(isBusy: isBusy)"))
        #expect(modifier.contains("placement: .cancellationAction"))
        #expect(modifier.contains("placement: .confirmationAction"))
        #expect(modifier.contains(".presentationBackground(Color.ink.paper)"))
        #expect(modifier.contains("InkSheetChrome.cancelKey"))
        #expect(modifier.contains("InkSheetChrome.closeKey"))
        #expect(modifier.contains("confirm.catalogKey"))
        #expect(!modifier.contains("\"Bitti\""))
        // Every toolbar item drops the iOS 26 glass capsule.
        let items = modifier.components(separatedBy: "ToolbarItem(placement:").count - 1
        let hidden = modifier.components(separatedBy: ".sharedBackgroundVisibility(.hidden)").count - 1
        #expect(items == 3)
        #expect(hidden == items)
        let style = try Self.section(of: source, startingAt: "struct InkSheetButtonStyle:")
        #expect(style.contains("InkSheetChrome.token(for: button, isEnabled: isEnabled)"))
        #expect(style.contains("InkSheetChrome.isEmphasized(button)"))
        #expect(style.contains("InkButtonChrome.minimumHeight"))
        #expect(!style.contains("Capsule"))
    }

    @Test func inkToggleAppliesTheAccentTint() throws {
        let source = try Self.read("App/Design/Components/InkSheet.swift")
        let function = try Self.section(of: source, startingAt: "func inkToggle()", until: "\n    }")
        #expect(function.contains("tint(Color.ink.accent)"))
        let modifier = try Self.section(of: source, startingAt: "struct InkSheetModifier:")
        #expect(modifier.contains(".inkToggle()"), "sheet content inherits the accent tint")
    }

    // MARK: - Support

    /// Text from `marker` to the next top-level declaration (or `until`).
    private static func section(
        of source: String, startingAt marker: String, until terminator: String = "\n}\n"
    ) throws -> String {
        let start = try #require(source.range(of: marker), "\(marker) not found")
        let rest = source[start.lowerBound...]
        let end = rest.range(of: terminator)?.upperBound ?? rest.endIndex
        return String(rest[..<end])
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
