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

private struct InkHeaderActionSlotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the `actions` slot of a manşet row (set by ``InkPageHeader``).
    var isInkHeaderActionSlot: Bool {
        get { self[InkHeaderActionSlotKey.self] }
        set { self[InkHeaderActionSlotKey.self] = newValue }
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

    #if os(macOS)
        @Environment(\.isInkHeaderActionSlot) private var isHeaderSlot
    #endif

    var body: some View {
        #if os(macOS)
            // Mac: search lives in the window toolbar only; the manşet rows show no magnifier.
            if !isHeaderSlot { button }
        #else
            button
        #endif
    }

    private var button: some View {
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
