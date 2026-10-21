import SwiftUI
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// The shell gate, the split shell's column tier, and the one table between phone tabs and
/// sidebar sections (`docs/screens.md`, "Bölünmüş kabuk").
struct AdaptiveShellTests {
    #if os(iOS)
        struct GateCase: Sendable, CustomTestStringConvertible {
            let horizontal: UserInterfaceSizeClass?
            let vertical: UserInterfaceSizeClass?
            let shell: ShellKind
            let scene: String
            var testDescription: String { scene }
        }

        /// Every size-class pair an iPhone scene reports, and the shell it gets.
        @Test(arguments: [
            GateCase(horizontal: .compact, vertical: .regular, shell: .tabs, scene: "portrait, Duo cover screen"),
            GateCase(horizontal: .compact, vertical: .compact, shell: .tabs, scene: "landscape phone"),
            GateCase(horizontal: .regular, vertical: .compact, shell: .tabs, scene: "Pro Max landscape"),
            GateCase(horizontal: .regular, vertical: .regular, shell: .split, scene: "Duo inner screen"),
            GateCase(horizontal: nil, vertical: .regular, shell: .tabs, scene: "width class unknown"),
            GateCase(horizontal: .regular, vertical: nil, shell: .tabs, scene: "height class unknown"),
        ])
        func gateReadsBothSizeClasses(_ gate: GateCase) {
            #expect(ShellKind.resolve(horizontal: gate.horizontal, vertical: gate.vertical) == gate.shell)
        }
    #endif

    /// 1000 pt: the Mac window's smallest width, where sidebar, list and page fit side by side.
    @Test func tierChangesAtTheMacWindowMinimum() {
        #expect(ShellTier.resolve(width: 626) == .twoColumns)
        #expect(ShellTier.resolve(width: 890) == .twoColumns)
        #expect(ShellTier.resolve(width: 999.5) == .twoColumns)
        #expect(ShellTier.resolve(width: 1000) == .threeColumns)
        #expect(ShellTier.resolve(width: 1280) == .threeColumns)
    }

    struct TierCase: Sendable, CustomTestStringConvertible {
        let width: CGFloat
        let columns: NavigationSplitViewVisibility
        let board: NavigationSplitViewVisibility
        let window: String
        var testDescription: String { window }
    }

    /// Below 1000 pt list and detail share the width and a board or a page takes all of it;
    /// from 1000 pt every column stands side by side (an upright 13" iPad as well).
    @Test(arguments: [
        TierCase(width: 626, columns: .doubleColumn, board: .detailOnly, window: "Duo inner screen, tent"),
        TierCase(width: 744, columns: .doubleColumn, board: .detailOnly, window: "iPad mini, portrait"),
        TierCase(width: 834, columns: .doubleColumn, board: .detailOnly, window: "iPad 11\", portrait"),
        TierCase(width: 890, columns: .doubleColumn, board: .detailOnly, window: "Duo inner screen, flat"),
        TierCase(width: 999.5, columns: .doubleColumn, board: .detailOnly, window: "just under the tier"),
        TierCase(width: 1000, columns: .all, board: .all, window: "Mac window minimum"),
        TierCase(width: 1032, columns: .all, board: .all, window: "iPad 13\", portrait"),
        TierCase(width: 1210, columns: .all, board: .all, window: "iPad 11\", landscape"),
        TierCase(width: 1376, columns: .all, board: .all, window: "iPad 13\", landscape"),
    ])
    func columnVisibilityFollowsTheWidth(_ tier: TierCase) {
        #expect(ShellStyle.columnVisibility(layout: .columns, width: tier.width) == tier.columns)
        #expect(ShellStyle.columnVisibility(layout: .board, width: tier.width) == tier.board)
        #expect(ShellStyle.columnVisibility(layout: .page, width: tier.width) == tier.board)
    }

    /// Before the first measurement the shell leaves the columns alone.
    @Test func unmeasuredWidthLeavesTheColumns() {
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 0) == nil)
        #expect(ShellStyle.columnVisibility(layout: .board, width: 0) == nil)
    }

    /// Before the first measurement the environment's tier is three columns, so a full-screen
    /// iPad's sidebar does not open at the two-column width and then grow.
    @Test func unmeasuredShellAssumesThreeColumns() {
        #expect(ShellTier.resolve(measuredWidth: 0) == .threeColumns)
        #expect(ShellTier.resolve(measuredWidth: 890) == .twoColumns)
        #expect(ShellTier.resolve(measuredWidth: 1032) == .threeColumns)
    }

    /// From 1000 pt every column comes back only when the tier is entered; a reset within the
    /// tier (a layout switch, a resize, a sidebar choice) keeps a sidebar the user put away.
    /// Below 1000 pt every reset asks again, as before.
    @Test func threeColumnsComeBackOnlyWhenTheTierIsEntered() {
        // Entering: the first measurement, a turn from upright 11" or the Duo's width.
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 1032, previousWidth: 0) == .all)
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 1376, previousWidth: 834) == .all)
        #expect(ShellStyle.columnVisibility(layout: .board, width: 1210, previousWidth: 834) == .all)
        // Within the tier: a turn of the 13", a Split View drag, a layout switch.
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 1032, previousWidth: 1376) == nil)
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 1100, previousWidth: 1376) == nil)
        #expect(ShellStyle.columnVisibility(layout: .board, width: 1376, previousWidth: 1376) == nil)
        // Below the tier nothing changed.
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 834, previousWidth: 1376) == .doubleColumn)
        #expect(ShellStyle.columnVisibility(layout: .page, width: 890, previousWidth: 890) == .detailOnly)
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 0, previousWidth: 1376) == nil)
    }

    /// From 1000 pt a switch between the columns and a board or page keeps a hidden sidebar
    /// hidden in the other split view's terms; the list column is never lost with it.
    @Test func layoutFamilySwitchTranslatesAHiddenSidebar() {
        func reset(_ layout: MacShellLayout, from previous: MacShellLayout, _ current: NavigationSplitViewVisibility)
            -> NavigationSplitViewVisibility?
        {
            ShellStyle.columnVisibility(
                layout: layout, width: 1376, previousWidth: 1376, previousLayout: previous, current: current)
        }
        // Board or page, sidebar away → columns: list and detail, not the detail alone.
        #expect(reset(.columns, from: .board, .detailOnly) == .doubleColumn)
        #expect(reset(.columns, from: .page, .detailOnly) == .doubleColumn)
        // Columns, sidebar away → board or page: the board alone.
        #expect(reset(.board, from: .columns, .doubleColumn) == .detailOnly)
        #expect(reset(.page, from: .columns, .doubleColumn) == .detailOnly)
        // Every column shown, or the same family: nothing to translate.
        #expect(reset(.columns, from: .board, .all) == nil)
        #expect(reset(.board, from: .columns, .all) == nil)
        #expect(reset(.page, from: .board, .detailOnly) == nil)
        #expect(reset(.columns, from: .columns, .doubleColumn) == nil)
        // Below the tier the Duo's values stay.
        #expect(
            ShellStyle.columnVisibility(
                layout: .columns, width: 890, previousWidth: 890, previousLayout: .board, current: .detailOnly)
                == .doubleColumn)
    }

    /// The Mac and the two-column tier keep the Mac sidebar; an iPad's three columns widen it
    /// for iOS type, and on iOS both tiers widen more at accessibility sizes.
    @Test func sidebarWidthFollowsTierAndTextSize() {
        #expect(ShellStyle.sidebarWidth(tier: .twoColumns, dynamicTypeSize: .large) == .macSidebar)
        #if os(iOS)
            #expect(
                ShellStyle.sidebarWidth(tier: .twoColumns, dynamicTypeSize: .accessibility3)
                    == ShellStyle.accessibilitySidebarWidth)
        #else
            #expect(ShellStyle.sidebarWidth(tier: .twoColumns, dynamicTypeSize: .accessibility3) == .macSidebar)
        #endif
        #if os(iOS)
            let regular = ShellStyle.sidebarWidth(tier: .threeColumns, dynamicTypeSize: .large)
            #expect(regular == ShellColumnWidth(min: 200, ideal: 240, max: 280))
            #expect(ShellStyle.sidebarWidth(tier: .threeColumns, dynamicTypeSize: .xxxLarge) == regular)
            #expect(
                ShellStyle.sidebarWidth(tier: .threeColumns, dynamicTypeSize: .accessibility3)
                    == ShellColumnWidth(min: 240, ideal: 280, max: 320))
            // An upright 13" iPad still keeps a readable detail beside sidebar and list.
            #expect(1032 - regular.ideal - InkSpacing.macListIdealWidth >= 440)
        #else
            #expect(ShellStyle.sidebarWidth(tier: .threeColumns, dynamicTypeSize: .accessibility3) == .macSidebar)
        #endif
        #expect(ShellColumnWidth.macSidebar == ShellColumnWidth(min: 180, ideal: 200, max: 240))
    }

    /// The Kişiler column's text buttons: "Rehberden aktar" joins "Yeni kişi" on iOS (the split
    /// shell's column, as on the phone page); the Mac has no contact picker. "Yeni tip…" closes
    /// every kind's list; a custom type the vault defines gets its own create button.
    @Test func entitiesColumnActionsFollowTheKindAndPlatform() {
        let none = EntityTypeCatalog()
        #if os(iOS)
            #expect(
                EntityColumnAction.actions(forList: "person", types: none) == [
                    .create(.person), .importContacts, .newType,
                ])
        #else
            #expect(EntityColumnAction.actions(forList: "person", types: none) == [.create(.person), .newType])
        #endif
        #expect(EntityColumnAction.actions(forList: "place", types: none) == [.create(.place), .newType])
        #expect(EntityColumnAction.actions(forList: "project", types: none) == [.newType])
        let project = EntityTypeDefinition(
            id: "project", folder: "projects", name: .init(tr: "Proje", en: "Project"),
            plural: .init(tr: "Projeler", en: "Projects"), icon: "folder.fill")
        #expect(
            EntityColumnAction.actions(forList: "project", types: EntityTypeCatalog(types: [project])) == [
                .create(.custom("project")), .newType,
            ])
    }

    /// A tab opens a section it holds, and that section leads back to the same tab.
    @Test func everyTabOpensItsOwnSection() {
        #expect(
            PhoneTab.allCases.map(\.desktopSection) == [.today, .days, .tasks, .people, .goals])
        for tab in PhoneTab.allCases {
            #expect(tab.desktopSection.phoneTab == tab, "\(tab)")
        }
    }

    /// Sections without a tab open inside the tab that links to them on iPhone.
    @Test func sectionsWithoutATabLandInTheTabThatHoldsThem() {
        #expect(DesktopSection.summaries.phoneTab == .days)
        #expect(DesktopSection.places.phoneTab == .entities)
        #expect(DesktopSection.graph.phoneTab == .entities)
        #expect(DesktopSection.map.phoneTab == .entities)
        #expect(Set(DesktopSection.allCases.map(\.phoneTab)) == Set(PhoneTab.allCases), "every tab has a section")
    }
}
