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

private struct SearchSheetKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the search sheet (set by ``SearchView``), where ``SearchButton`` returns
    /// from an opened page to the results.
    var isSearchSheet: Bool {
        get { self[SearchSheetKey.self] }
        set { self[SearchSheetKey.self] = newValue }
    }
}

/// Opens global search through `\.openSearch`.
///
/// iPhone: belongs in the `actions` slot of a manşet row (``InkPageTitle`` /
/// ``InkPageTitleRow`` / ``InkPageHeader``) as the **last** (rightmost) icon. The slot styles
/// every plain button in it with ``InkHeaderButtonStyle`` (utility role), so there this draws
/// exactly like an ``InkHeaderAction``: frameless, secondary text color, 44 pt target. It must
/// not go in `.toolbar` there.
///
/// Mac: search has one place, the window toolbar of the shell (`MacNavigation`). The same
/// screens are shared, so inside a manşet row's `actions` slot this view draws nothing on Mac.
/// The exception is the search sheet: a page opened from the results keeps the manşet
/// magnifier, which leads back to the results (the window toolbar is behind the sheet).
///
/// The body stays a bare system button on purpose: the Mac toolbar draws it as its own glass
/// control and the manşet slot supplies the iPhone look (`ControlPatternUsageTests`).
struct SearchButton: View {
    @Environment(\.openSearch) private var openSearch

    #if os(macOS)
        @Environment(\.isInkHeaderActionSlot) private var isHeaderSlot
        @Environment(\.isSearchSheet) private var isSearchSheet
    #endif

    var body: some View {
        #if os(macOS)
            // Mac: search lives in the window toolbar only; the manşet rows show no magnifier,
            // except inside the search sheet, where it is the way back to the results.
            if !isHeaderSlot || isSearchSheet { button }
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
