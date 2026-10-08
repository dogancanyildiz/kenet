import SwiftUI

/// The single confirm word of an editing sheet.
enum InkSheetConfirmation: Equatable, Sendable {
    /// "Kaydet": the sheet changes an existing record.
    case save
    /// "Oluştur": the sheet opens a new record.
    case create

    /// String Catalog key.
    var catalogKey: String {
        switch self {
        case .save: "Kaydet"
        case .create: "Oluştur"
        }
    }
}

/// Pure rules for the sheet toolbar (unit-tested; ``InkSheetModifier`` calls these).
enum InkSheetChrome {
    enum Button: Equatable, Sendable {
        /// Left, editing sheet: "Vazgeç".
        case cancel
        /// Right, editing sheet: "Kaydet" / "Oluştur".
        case confirm
        /// Right, read-only sheet: "Kapat".
        case close
    }

    /// String Catalog keys, defined once for every sheet. "Bitti" is not used.
    static let cancelKey = "Vazgeç"
    static let closeKey = "Kapat"

    /// Mac sheet minimum width (pt). Without an explicit size a `List` reports ~0 ideal height
    /// and the sheet collapses to a title bar (entity edit).
    static let macMinWidth: CGFloat = 480
    /// Mac sheet ideal width (pt).
    static let macIdealWidth: CGFloat = 520
    /// Mac sheet minimum height (pt): enough for the serif manşet plus a short form.
    static let macMinHeight: CGFloat = 360
    /// Mac sheet ideal height (pt).
    static let macIdealHeight: CGFloat = 480

    static func token(for button: Button, isEnabled: Bool = true) -> InkButtonChrome.Token {
        // "Vazgeç" is secondary text while enabled, so its disabled state steps down to the
        // control line color; the accent words fall back to secondary text.
        guard isEnabled else { return button == .cancel ? .control : .secondaryText }
        switch button {
        case .cancel: return .secondaryText
        case .confirm, .close: return .accent
        }
    }

    /// Only the confirm word is semibold.
    static func isEmphasized(_ button: Button) -> Bool { button == .confirm }

    /// Confirm is tappable only when the caller allows it and no write is in flight.
    static func isConfirmEnabled(isEnabled: Bool, isBusy: Bool) -> Bool { isEnabled && !isBusy }

    /// While busy the confirm word is replaced by a progress indicator.
    static func showsProgress(isBusy: Bool) -> Bool { isBusy }

    /// Buttons of a cancel-only sheet: "Vazgeç" alone, or nothing once the page holds the only
    /// way out (`showsCancel == false`). There is never a confirm word.
    static func cancelOnlyButtons(showsCancel: Bool) -> [Button] { showsCancel ? [.cancel] : [] }

    /// Mac sheets need a non-zero proposed height so `List` / `ScrollView` content lays out.
    static func macContentFits(minHeight: CGFloat) -> Bool { minHeight >= macMinHeight }
}

extension View {
    /// Editing sheet chrome: paper background (including the presentation background), hidden
    /// system title, accent tint for system controls, and a plain-text toolbar: "Vazgeç" on the
    /// left, one confirm word on the right. No glass capsule, no filled button.
    ///
    /// On Mac the system window title is removed (serif manşet only), the action words sit on a
    /// bottom paper bar (leading cancel, trailing confirm), and a non-zero ideal size keeps
    /// `List` bodies from collapsing. iPhone keeps the top toolbar placements.
    ///
    /// Apply to the sheet's content **inside** its `NavigationStack`. The serif manşet is the
    /// content's first scrolled child (`InkPageTitleRow(title)` in a `List`,
    /// `InkPageTitle(title)` in a `ScrollView`), or use ``InkSheetScaffold`` which adds it.
    ///
    /// - Parameters:
    ///   - title: navigation title (not drawn; feeds accessibility and the Mac window).
    ///   - confirm: `.save` ("Kaydet") or `.create` ("Oluştur").
    ///   - isConfirmEnabled: `false` while the form is invalid or unchanged.
    ///   - isBusy: `true` while writing; confirm is disabled and shows progress.
    ///   - isCancelEnabled: `false` while "Vazgeç" must not be used (a write in flight); the
    ///     word is drawn disabled instead of being silently ignored.
    ///   - cancelIdentifier / confirmIdentifier: accessibility identifiers of the two buttons.
    ///   - onCancel: "Vazgeç" (also Esc). `nil` dismisses. A screen with an unsaved-changes
    ///     dialog passes its own closure and keeps the `confirmationDialog` itself.
    ///   - onConfirm: the confirm action (also Return on Mac). It does not dismiss by itself.
    func inkSheet(
        _ title: LocalizedStringKey, confirm: InkSheetConfirmation = .save,
        isConfirmEnabled: Bool = true, isBusy: Bool = false, isCancelEnabled: Bool = true,
        cancelIdentifier: String? = nil, confirmIdentifier: String? = nil,
        onCancel: (() -> Void)? = nil, onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            InkSheetModifier(
                kind: .editing(
                    confirm: confirm, isConfirmEnabled: isConfirmEnabled, isBusy: isBusy,
                    isCancelEnabled: isCancelEnabled, cancelIdentifier: cancelIdentifier,
                    confirmIdentifier: confirmIdentifier, onCancel: onCancel, onConfirm: onConfirm))
        )
        .inkSheetNavigationTitle(title)
    }

    /// Editing sheet chrome with a non-localized title (e.g. an entity name).
    func inkSheet(
        verbatim title: String, confirm: InkSheetConfirmation = .save,
        isConfirmEnabled: Bool = true, isBusy: Bool = false, isCancelEnabled: Bool = true,
        cancelIdentifier: String? = nil, confirmIdentifier: String? = nil,
        onCancel: (() -> Void)? = nil, onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            InkSheetModifier(
                kind: .editing(
                    confirm: confirm, isConfirmEnabled: isConfirmEnabled, isBusy: isBusy,
                    isCancelEnabled: isCancelEnabled, cancelIdentifier: cancelIdentifier,
                    confirmIdentifier: confirmIdentifier, onCancel: onCancel, onConfirm: onConfirm))
        )
        .inkSheetNavigationTitle(verbatim: title)
    }

    /// Read-only sheet chrome: same background and title rules, one button: "Kapat" on the
    /// right (also Esc). `onClose: nil` dismisses.
    func inkSheet(
        _ title: LocalizedStringKey, closeIdentifier: String? = nil, onClose: (() -> Void)? = nil
    ) -> some View {
        modifier(InkSheetModifier(kind: .reading(closeIdentifier: closeIdentifier, onClose: onClose)))
            .inkSheetNavigationTitle(title)
    }

    /// Read-only sheet chrome with a non-localized title.
    func inkSheet(
        verbatim title: String, closeIdentifier: String? = nil, onClose: (() -> Void)? = nil
    ) -> some View {
        modifier(InkSheetModifier(kind: .reading(closeIdentifier: closeIdentifier, onClose: onClose)))
            .inkSheetNavigationTitle(verbatim: title)
    }

    /// Cancel-only sheet chrome: same background and title rules, one button: "Vazgeç" on the
    /// left (also Esc). For a sheet whose action is not a save and therefore lives in the page
    /// as a button (vault preparation: "Uygula"); nothing is bound to Return.
    ///
    /// - Parameters:
    ///   - cancelIdentifier: accessibility identifier of "Vazgeç" (required label: it tells this
    ///     overload from the read-only one).
    ///   - showsCancel: `false` leaves the bar empty (the page holds the only way out) without
    ///     changing the identity of the content.
    ///   - isCancelEnabled: `false` draws "Vazgeç" disabled (a write in flight).
    ///   - onCancel: "Vazgeç". `nil` dismisses.
    func inkSheet(
        _ title: LocalizedStringKey, cancelIdentifier: String?, showsCancel: Bool = true,
        isCancelEnabled: Bool = true, onCancel: (() -> Void)? = nil
    ) -> some View {
        modifier(
            InkSheetModifier(
                kind: .cancelOnly(
                    cancelIdentifier: cancelIdentifier, showsCancel: showsCancel,
                    isCancelEnabled: isCancelEnabled, onCancel: onCancel))
        )
        .inkSheetNavigationTitle(title)
    }

    /// Cancel-only sheet chrome with a non-localized title.
    func inkSheet(
        verbatim title: String, cancelIdentifier: String?, showsCancel: Bool = true,
        isCancelEnabled: Bool = true, onCancel: (() -> Void)? = nil
    ) -> some View {
        modifier(
            InkSheetModifier(
                kind: .cancelOnly(
                    cancelIdentifier: cancelIdentifier, showsCancel: showsCancel,
                    isCancelEnabled: isCancelEnabled, onCancel: onCancel))
        )
        .inkSheetNavigationTitle(verbatim: title)
    }

    /// Accent tint for system controls (`Toggle`, `Stepper`, `DatePicker`, `ProgressView`).
    /// A switch is system green unless a tint reaches it; put this on the control or on any
    /// container (a whole `List`). ``inkSheet(_:closeIdentifier:onClose:)`` already applies it.
    func inkToggle() -> some View {
        tint(Color.ink.accent)
    }
}

/// Sheet body for content that is not a `List`: a scroll view whose first child is the serif
/// manşet, then `content` at the page margin, with the ``View/inkSheet(_:closeIdentifier:onClose:)``
/// chrome. Use inside the sheet's `NavigationStack`. `List`-based sheets use the `.inkSheet`
/// modifier and an ``InkPageTitleRow`` instead.
struct InkSheetScaffold<Content: View>: View {
    private let title: LocalizedStringKey
    private let byline: String?
    private let kind: InkSheetModifier.Kind
    private let content: Content

    /// Editing sheet: "Vazgeç" and one confirm word. Parameters as in the `.inkSheet` modifier.
    init(
        _ title: LocalizedStringKey, byline: String? = nil,
        confirm: InkSheetConfirmation = .save, isConfirmEnabled: Bool = true,
        isBusy: Bool = false, isCancelEnabled: Bool = true, cancelIdentifier: String? = nil,
        confirmIdentifier: String? = nil, onCancel: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.byline = byline
        kind = .editing(
            confirm: confirm, isConfirmEnabled: isConfirmEnabled, isBusy: isBusy,
            isCancelEnabled: isCancelEnabled, cancelIdentifier: cancelIdentifier,
            confirmIdentifier: confirmIdentifier, onCancel: onCancel, onConfirm: onConfirm)
        self.content = content()
    }

    /// Read-only sheet: "Kapat" only.
    init(
        _ title: LocalizedStringKey, byline: String? = nil, closeIdentifier: String? = nil,
        onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.byline = byline
        kind = .reading(closeIdentifier: closeIdentifier, onClose: onClose)
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                InkPageTitle(title, byline: byline)
                content
                    .padding(.horizontal, InkSpacing.margin)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(InkSheetModifier(kind: kind))
        .inkSheetNavigationTitle(title)
    }
}

/// Background, tint and toolbar of a sheet. The title modifier is applied by the callers above.
struct InkSheetModifier: ViewModifier {
    enum Kind {
        case editing(
            confirm: InkSheetConfirmation, isConfirmEnabled: Bool, isBusy: Bool,
            isCancelEnabled: Bool = true, cancelIdentifier: String?, confirmIdentifier: String?,
            onCancel: (() -> Void)?, onConfirm: () -> Void)
        case reading(closeIdentifier: String?, onClose: (() -> Void)?)
        case cancelOnly(
            cancelIdentifier: String?, showsCancel: Bool, isCancelEnabled: Bool,
            onCancel: (() -> Void)?)
    }

    let kind: Kind
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        let page =
            content
            .inkPage()
            .inkToggle()
            .presentationBackground(Color.ink.paper)
        #if os(macOS)
            // Mac: paper chrome, bottom action bar, non-zero ideal size so List content does
            // not collapse. Sans title is omitted via ``inkSheetNavigationTitle``.
            page
                .toolbarBackground(Color.ink.paper, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .safeAreaInset(edge: .bottom, spacing: 0) { macActionBar }
                .frame(
                    minWidth: InkSheetChrome.macMinWidth, idealWidth: InkSheetChrome.macIdealWidth,
                    minHeight: InkSheetChrome.macMinHeight, idealHeight: InkSheetChrome.macIdealHeight
                )
        #else
            page
                .toolbar {
                    // iOS 26 draws every toolbar item in a glass capsule; hiding the shared
                    // background leaves the plain word while keeping the system placements.
                    switch kind {
                    case .editing(
                        let confirm, let isConfirmEnabled, let isBusy, let isCancelEnabled,
                        let cancelIdentifier, let confirmIdentifier, let onCancel, let onConfirm):
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                if let onCancel { onCancel() } else { dismiss() }
                            } label: {
                                Text(LocalizedStringKey(InkSheetChrome.cancelKey))
                            }
                            .buttonStyle(InkSheetButtonStyle(button: .cancel))
                            .disabled(!isCancelEnabled)
                            .inkSheetShortcut(.cancelAction)
                            .inkAccessibilityIdentifier(cancelIdentifier)
                        }
                        .sharedBackgroundVisibility(.hidden)
                        ToolbarItem(placement: .confirmationAction) {
                            Button(action: onConfirm) {
                                Text(LocalizedStringKey(confirm.catalogKey))
                                    .opacity(InkSheetChrome.showsProgress(isBusy: isBusy) ? 0 : 1)
                                    .overlay {
                                        if InkSheetChrome.showsProgress(isBusy: isBusy) {
                                            ProgressView().controlSize(.small)
                                        }
                                    }
                            }
                            .buttonStyle(InkSheetButtonStyle(button: .confirm))
                            .disabled(
                                !InkSheetChrome.isConfirmEnabled(
                                    isEnabled: isConfirmEnabled, isBusy: isBusy)
                            )
                            .inkSheetShortcut(.defaultAction)
                            .inkAccessibilityIdentifier(confirmIdentifier)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    case .reading(let closeIdentifier, let onClose):
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                if let onClose { onClose() } else { dismiss() }
                            } label: {
                                Text(LocalizedStringKey(InkSheetChrome.closeKey))
                            }
                            .buttonStyle(InkSheetButtonStyle(button: .close))
                            .inkSheetShortcut(.cancelAction)
                            .inkAccessibilityIdentifier(closeIdentifier)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    case .cancelOnly(
                        let cancelIdentifier, let showsCancel, let isCancelEnabled, let onCancel):
                        if InkSheetChrome.cancelOnlyButtons(showsCancel: showsCancel).contains(.cancel) {
                            InkSheetCancelItem(
                                identifier: cancelIdentifier, isEnabled: isCancelEnabled,
                                action: { if let onCancel { onCancel() } else { dismiss() } })
                        }
                    }
                }
        #endif
    }

    #if os(macOS)
        /// Bottom paper bar: cancel leading, confirm/close trailing (design pattern 6).
        @ViewBuilder private var macActionBar: some View {
            HStack(spacing: 0) {
                switch kind {
                case .editing(
                    let confirm, let isConfirmEnabled, let isBusy, let isCancelEnabled,
                    let cancelIdentifier, let confirmIdentifier, let onCancel, let onConfirm):
                    macBarButton(
                        .cancel, key: InkSheetChrome.cancelKey, identifier: cancelIdentifier,
                        isEnabled: isCancelEnabled, shortcut: .cancelAction
                    ) {
                        if let onCancel { onCancel() } else { dismiss() }
                    }
                    Spacer(minLength: 12)
                    macBarButton(
                        .confirm, key: confirm.catalogKey, identifier: confirmIdentifier,
                        isEnabled: InkSheetChrome.isConfirmEnabled(
                            isEnabled: isConfirmEnabled, isBusy: isBusy),
                        showsProgress: InkSheetChrome.showsProgress(isBusy: isBusy),
                        shortcut: .defaultAction, action: onConfirm
                    )
                case .reading(let closeIdentifier, let onClose):
                    Spacer(minLength: 0)
                    macBarButton(
                        .close, key: InkSheetChrome.closeKey, identifier: closeIdentifier,
                        shortcut: .cancelAction
                    ) {
                        if let onClose { onClose() } else { dismiss() }
                    }
                case .cancelOnly(let cancelIdentifier, let showsCancel, let isCancelEnabled, let onCancel):
                    if InkSheetChrome.cancelOnlyButtons(showsCancel: showsCancel).contains(.cancel) {
                        macBarButton(
                            .cancel, key: InkSheetChrome.cancelKey, identifier: cancelIdentifier,
                            isEnabled: isCancelEnabled, shortcut: .cancelAction
                        ) {
                            if let onCancel { onCancel() } else { dismiss() }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, InkSpacing.margin)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.ink.paper)
        }

        private func macBarButton(
            _ button: InkSheetChrome.Button, key: String, identifier: String?,
            isEnabled: Bool = true, showsProgress: Bool = false, shortcut: KeyboardShortcut,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Text(LocalizedStringKey(key))
                    .opacity(showsProgress ? 0 : 1)
                    .overlay {
                        if showsProgress { ProgressView().controlSize(.small) }
                    }
            }
            .buttonStyle(InkSheetButtonStyle(button: button))
            .disabled(!isEnabled)
            .inkSheetShortcut(shortcut)
            .inkAccessibilityIdentifier(identifier)
        }
    #endif
}

/// "Vazgeç" of a cancel-only sheet: the same word, placement, Esc shortcut and capsule-free
/// drawing as the editing sheet's cancel button.
private struct InkSheetCancelItem: ToolbarContent {
    var identifier: String?
    var isEnabled: Bool
    var action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: action) {
                Text(LocalizedStringKey(InkSheetChrome.cancelKey))
            }
            .buttonStyle(InkSheetButtonStyle(button: .cancel))
            .disabled(!isEnabled)
            .inkSheetShortcut(.cancelAction)
            .inkAccessibilityIdentifier(identifier)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Plain-text toolbar word: token color, no capsule, 44 pt target.
private struct InkSheetButtonStyle: ButtonStyle {
    var button: InkSheetChrome.Button
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let token =
            configuration.isPressed
            ? InkButtonChrome.Token.text : InkSheetChrome.token(for: button, isEnabled: isEnabled)
        return configuration.label
            .font(Font.ink.byline)
            .fontWeight(InkSheetChrome.isEmphasized(button) ? .semibold : .regular)
            .foregroundStyle(InkButtonChrome.color(for: token))
            .lineLimit(1)
            .fixedSize()
            .frame(minHeight: InkButtonChrome.minimumHeight)
            .contentShape(Rectangle())
            // A bar is one fixed-height row: like the quick-entry chrome, the words stop at AX2.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

extension View {
    /// Esc / Return on Mac sheets. iOS keeps the system behavior of the toolbar placements.
    @ViewBuilder fileprivate func inkSheetShortcut(_ shortcut: KeyboardShortcut) -> some View {
        #if os(macOS)
            keyboardShortcut(shortcut)
        #else
            self
        #endif
    }

    /// Sheet navigation title: on iPhone the system bar title is set then hidden (back history).
    /// On Mac the sans title must be an explicit blank: leaving it unset lets the stack infer the
    /// manşet text into the toolbar; the default title item is also removed.
    @ViewBuilder fileprivate func inkSheetNavigationTitle(_ title: LocalizedStringKey) -> some View {
        #if os(macOS)
            navigationTitle(" ")
                .toolbar(removing: .title)
        #else
            inkPageNavigationTitle(title)
        #endif
    }

    @ViewBuilder fileprivate func inkSheetNavigationTitle(verbatim title: String) -> some View {
        #if os(macOS)
            navigationTitle(" ")
                .toolbar(removing: .title)
        #else
            inkPageNavigationTitle(verbatim: title)
        #endif
    }

    /// Closures that dismiss the outermost sheet, not a pushed navigation destination.
    /// Search sets this so a nested note can expose "Kapat" that closes the whole sheet.
    func inkSheetDismissAction(_ action: @escaping @MainActor @Sendable () -> Void) -> some View {
        environment(\.inkSheetDismissAction, action)
    }
}

/// Dismisses the sheet presentation (not a `NavigationStack` push). Default is `nil`.
private struct InkSheetDismissActionKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable () -> Void)? = nil
}

extension EnvironmentValues {
    var inkSheetDismissAction: (@MainActor @Sendable () -> Void)? {
        get { self[InkSheetDismissActionKey.self] }
        set { self[InkSheetDismissActionKey.self] = newValue }
    }
}
