import SwiftUI

/// The navigation shell the main window shows (`docs/screens.md`, "Bölünmüş kabuk").
enum ShellKind: Equatable, Sendable {
    /// Bottom tab bar, one stack per tab (`PhoneNavigation`).
    case tabs
    /// Sidebar, list column and detail (`MacNavigation`): the Mac window, the iPhone Duo inner
    /// screen and an iPad window that is regular in both directions.
    case split

    #if os(iOS)
        /// Only a scene that is regular in both directions gets the split shell: the iPhone Duo
        /// inner screen in every pose and a full-screen iPad window. An iPhone Pro Max in
        /// landscape is regular × compact, an iPad in a narrow Split View or Slide Over compact
        /// × regular: both keep the tabs. The device idiom and the screen size are never asked.
        static func resolve(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> Self {
            horizontal == .regular && vertical == .regular ? .split : .tabs
        }
    #endif
}

/// How many columns the split shell keeps side by side, from the width it is given.
enum ShellTier: Equatable, Sendable {
    /// Narrower than ``ShellStyle/threeColumnMinWidth`` (the iPhone Duo inner screen, about
    /// 890 × 626 pt): the sidebar hides after a choice; list and detail share the width.
    case twoColumns
    /// The Mac window (never narrower) and an iPad window from 1000 pt (13" in both
    /// orientations, 11" in landscape): sidebar, list and detail side by side.
    case threeColumns

    static func resolve(width: CGFloat) -> Self {
        width < ShellStyle.threeColumnMinWidth ? .twoColumns : .threeColumns
    }

    /// The tier for the shell's environment, also before its first measurement (`0`): then
    /// three columns. On iOS the split view is built only after that measurement (one built
    /// before it lost its sidebar on some cold starts), so no column is drawn with this guess.
    static func resolve(measuredWidth width: CGFloat) -> Self {
        width > 0 ? resolve(width: width) : .threeColumns
    }
}

/// Split-shell tokens. The defaults leave the iPhone tab shell and the Mac window as they are:
/// nothing here applies until the split shell runs on iOS.
enum ShellStyle {
    /// Sidebar, list and a readable detail fit side by side from here: the Mac window's
    /// smallest width (200 + 320 + 480 pt).
    static let threeColumnMinWidth: CGFloat = InkSpacing.macWindowMinWidth

    /// iOS three-column sidebar: iOS type is larger than the Mac's (17 pt body against 13), so
    /// "Zaman çizelgesi" and a project name fit beside their icon. Upright 13" iPad: 240 + 320
    /// leaves the detail 472 pt.
    static let threeColumnSidebarWidth = ShellColumnWidth(min: 200, ideal: 240, max: 280)
    /// The same at accessibility text sizes: a name is cut at its end ("…"), never broken
    /// inside a word. Upright 13" iPad: 280 + 320 still leaves the detail 432 pt, so iPadOS
    /// keeps the three columns side by side.
    static let accessibilitySidebarWidth = ShellColumnWidth(min: 240, ideal: 280, max: 320)

    /// Sidebar width for the tier and text size. The Mac window and the two-column tier (the
    /// sidebar laid over the list on the iPhone Duo) keep the Mac widths.
    static func sidebarWidth(tier: ShellTier, dynamicTypeSize: DynamicTypeSize) -> ShellColumnWidth {
        #if os(iOS)
            guard tier == .threeColumns else { return .macSidebar }
            return dynamicTypeSize.isAccessibilitySize ? accessibilitySidebarWidth : threeColumnSidebarWidth
        #else
            .macSidebar
        #endif
    }

    /// Columns the split shell shows on iOS when a layout opens, the width changes or a sidebar
    /// row is chosen. `nil` (before the first measurement) leaves the visibility as it is.
    /// The Mac shell never asks: its window always holds three columns.
    static func columnVisibility(layout: MacShellLayout, width: CGFloat) -> NavigationSplitViewVisibility? {
        guard width > 0 else { return nil }
        // Every column side by side: left to the system, an upright 13" iPad (1032 pt) would
        // put the detail in front and lay the sidebar over it.
        guard ShellTier.resolve(width: width) == .twoColumns else { return .all }
        switch layout {
        // List and detail share the width; the sidebar button brings the sidebar back.
        case .columns: return .doubleColumn
        // Board and full-width pages take the whole width.
        case .board, .page: return .detailOnly
        }
    }

    /// What a reset asks for, given the width the shell had before (`0`: not measured yet), the
    /// layout it showed before and the visibility it holds now. Below 1000 pt every reset (a
    /// width change, a layout switch, a sidebar choice) asks again, as on the iPhone Duo. From
    /// 1000 pt entering the tier (the first measurement, a turn or a Split View resize across
    /// 1000 pt) brings every column back; within the tier a sidebar the user put away with its
    /// button stays away. A switch between the three-column layout and a board or page (two
    /// columns) translates that choice, since the two split views read a value differently:
    /// "detail only" on a board is "list and detail" in the columns, and back.
    static func columnVisibility(
        layout: MacShellLayout, width: CGFloat, previousWidth: CGFloat,
        previousLayout: MacShellLayout? = nil, current: NavigationSplitViewVisibility = .automatic
    ) -> NavigationSplitViewVisibility? {
        guard let visibility = columnVisibility(layout: layout, width: width) else { return nil }
        let stayed = previousWidth > 0 && ShellTier.resolve(width: previousWidth) == .threeColumns
        guard visibility == .all && stayed else { return visibility }
        let previousLayout = previousLayout ?? layout
        guard (previousLayout == .columns) != (layout == .columns) else { return nil }
        switch (layout, current) {
        // Board or page → columns, sidebar away: the list column comes with the detail.
        case (.columns, .detailOnly): return .doubleColumn
        // Columns → board or page, sidebar away: the board alone.
        case (.board, .doubleColumn), (.page, .doubleColumn): return .detailOnly
        default: return nil
        }
    }
}

/// A split view column's width range (`navigationSplitViewColumnWidth`).
struct ShellColumnWidth: Equatable, Sendable {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat

    /// The Mac sidebar (`docs/design.md`, "Biçim").
    static let macSidebar = ShellColumnWidth(
        min: InkSpacing.macSidebarMinWidth, ideal: InkSpacing.macSidebarIdealWidth,
        max: InkSpacing.macSidebarMaxWidth)
}

extension EnvironmentValues {
    /// The split shell's tier on iOS, from its measured width; the Mac window is always three
    /// columns.
    @Entry var shellTier: ShellTier = .threeColumns

    /// The shell the view is drawn in. `.tabs` until a split shell sets it, so phone chrome
    /// (a hidden navigation bar) stays as it is everywhere else.
    @Entry var shellKind: ShellKind = .tabs
}
