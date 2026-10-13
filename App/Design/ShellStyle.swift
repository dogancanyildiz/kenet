import SwiftUI

/// The navigation shell the main window shows (`docs/screens.md`, "iPhone Duo iç ekranı").
enum ShellKind: Equatable, Sendable {
    /// Bottom tab bar, one stack per tab (`PhoneNavigation`).
    case tabs
    /// Sidebar, list column and detail (`MacNavigation`): the Mac window and the iPhone Duo
    /// inner screen.
    case split

    #if os(iOS)
        /// Only a scene that is regular in both directions gets the split shell: the iPhone Duo
        /// inner screen in every pose. An iPhone Pro Max in landscape is regular × compact and
        /// keeps the tabs. The device idiom and the screen size are never asked.
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
    /// The Mac window (never narrower) and, later, an iPad. On iOS the system decides; this
    /// tier is not designed for iOS yet.
    case threeColumns

    static func resolve(width: CGFloat) -> Self {
        width < ShellStyle.threeColumnMinWidth ? .twoColumns : .threeColumns
    }
}

/// Split-shell tokens. The defaults leave the iPhone tab shell and the Mac window as they are:
/// nothing here applies until the split shell runs on iOS.
enum ShellStyle {
    /// Sidebar, list and a readable detail fit side by side from here: the Mac window's
    /// smallest width (200 + 320 + 480 pt).
    /// The sidebar keeps the Mac widths (``View/macSidebarColumn()``) on iOS too.
    static let threeColumnMinWidth: CGFloat = InkSpacing.macWindowMinWidth

    /// Columns the split shell shows on iOS when a layout opens, the width changes or a sidebar
    /// row is chosen. `nil` leaves the visibility as it is (the system's own, the user's toggle).
    /// The Mac shell never asks: its window always holds three columns.
    static func columnVisibility(layout: MacShellLayout, width: CGFloat) -> NavigationSplitViewVisibility? {
        guard width > 0, ShellTier.resolve(width: width) == .twoColumns else { return nil }
        switch layout {
        // List and detail share the width; the sidebar button brings the sidebar back.
        case .columns: return .doubleColumn
        // Board and full-width pages take the whole width.
        case .board, .page: return .detailOnly
        }
    }
}

extension EnvironmentValues {
    /// The shell the view is drawn in. `.tabs` until a split shell sets it, so phone chrome
    /// (a hidden navigation bar) stays as it is everywhere else.
    @Entry var shellKind: ShellKind = .tabs
}
