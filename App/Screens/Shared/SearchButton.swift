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

extension View {
    /// The global search sheet, presented above the shell (`ContentView`). In the split iOS
    /// shell (iPhone Duo inner screen, iPad) it is a form sheet like Settings, so the regular
    /// width's tall page sheet does not run under the software keyboard; the sheet takes the
    /// shell's kind, which `MacNavigation` sets only for the views below it.
    func searchSheet(isPresented: Binding<Bool>, store: IndexStore) -> some View {
        modifier(SearchSheetModifier(isPresented: isPresented, store: store))
    }
}

private struct SearchSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let store: IndexStore
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            #if os(iOS)
                SearchView(store: store)
                    .environment(\.openSearch, { isPresented = true })
                    .environment(\.shellKind, shellKind)
                    .modifier(SearchSheetSizing(shellKind: shellKind))
            #else
                SearchView(store: store)
                    .environment(\.openSearch, { isPresented = true })
            #endif
        }
    }

    #if os(iOS)
        private var shellKind: ShellKind {
            ShellKind.resolve(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
        }
    #endif
}

#if os(iOS)
    /// Split shell: the form size of the other sheets (``SearchSheetChrome``); the tab shell
    /// keeps the phone's full-height sheet. One view for both shells: a Split View drag that
    /// changes the size class while the sheet is open keeps the query typed.
    struct SearchSheetSizing: ViewModifier {
        let shellKind: ShellKind

        func body(content: Content) -> some View {
            let isForm = shellKind == .split
            content
                .frame(
                    minWidth: isForm ? InkSheetChrome.macMinWidth : nil,
                    idealWidth: isForm ? SearchSheetChrome.idealWidth : nil,
                    minHeight: isForm ? InkSheetChrome.macMinHeight : nil,
                    idealHeight: isForm ? SearchSheetChrome.idealHeight : nil
                )
                .presentationSizing(SearchSheetPresentationSizing(isForm: isForm))
        }
    }

    /// The form's fitted size in the split shell, the system's own sizing in the tab shell; one
    /// type, so the shell kind is a value and not a branch of the view tree.
    private struct SearchSheetPresentationSizing: PresentationSizing {
        let isForm: Bool

        func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
            if isForm {
                FormPresentationSizing.form.fitted(horizontal: false, vertical: true)
                    .proposedSize(for: root, context: context)
            } else {
                AutomaticPresentationSizing.automatic.proposedSize(for: root, context: context)
            }
        }
    }

    enum SearchSheetChrome {
        /// Width of the split shell's search sheet (pt): the iPad form sheet's.
        static let idealWidth: CGFloat = 580
        /// Height (pt): the manşet, the field and about five results stay above the software
        /// keyboard of a 13" iPad in landscape (its top at about 530 pt).
        static let idealHeight: CGFloat = 480
    }
#endif

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
