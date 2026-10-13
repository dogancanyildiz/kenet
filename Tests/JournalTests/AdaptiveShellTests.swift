import SwiftUI
import Testing

@testable import Journal

/// The shell gate, the split shell's column tier, and the one table between phone tabs and
/// sidebar sections (`docs/screens.md`, "iPhone Duo iç ekranı").
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

    /// Two-column tier: list and detail share the width, a board or a page takes all of it.
    /// From 1000 pt and before the first measurement the shell leaves the columns alone.
    @Test func twoColumnTierPutsTheSidebarAway() {
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 890) == .doubleColumn)
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 626) == .doubleColumn)
        #expect(ShellStyle.columnVisibility(layout: .board, width: 890) == .detailOnly)
        #expect(ShellStyle.columnVisibility(layout: .page, width: 890) == .detailOnly)
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 1000) == nil)
        #expect(ShellStyle.columnVisibility(layout: .board, width: 1280) == nil)
        #expect(ShellStyle.columnVisibility(layout: .columns, width: 0) == nil)
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
