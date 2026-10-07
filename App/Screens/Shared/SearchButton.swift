import SwiftUI

private struct OpenSearchKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var openSearch: @MainActor @Sendable () -> Void {
        get { self[OpenSearchKey.self] }
        set { self[OpenSearchKey.self] = newValue }
    }
}

/// Opens global search through `\.openSearch`.
///
/// Belongs in the `actions` slot of a manşet row (``InkPageTitle`` / ``InkPageTitleRow`` /
/// ``InkPageHeader``) as the **last** (rightmost) icon. The slot styles every plain button in
/// it with ``InkHeaderButtonStyle`` (utility role), so there this draws exactly like an
/// ``InkHeaderAction``: frameless, secondary text color, 44 pt target.
///
/// The body stays a bare system button on purpose: screens that still place it in `.toolbar`
/// keep compiling and keep their exact rendering until they move. New code must not put it
/// in `.toolbar` (`ControlPatternUsageTests`).
struct SearchButton: View {
    @Environment(\.openSearch) private var openSearch

    var body: some View {
        Button("Ara", systemImage: "magnifyingglass", action: openSearch)
            .labelStyle(.iconOnly)
    }
}

#if os(macOS)
    struct SearchNavigationKey: FocusedValueKey {
        typealias Value = () -> Void
    }

    extension FocusedValues {
        var openSearch: (() -> Void)? {
            get { self[SearchNavigationKey.self] }
            set { self[SearchNavigationKey.self] = newValue }
        }
    }
#endif
