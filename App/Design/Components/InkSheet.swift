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
}

extension View {
    /// Editing sheet chrome: paper background (including the presentation background), hidden
    /// system title, accent tint for system controls, and a plain-text toolbar: "Vazgeç" on the
    /// left, one confirm word on the right. No glass capsule, no filled button.
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
        .inkPageNavigationTitle(title)
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
        .inkPageNavigationTitle(verbatim: title)
    }

    /// Read-only sheet chrome: same background and title rules, one button: "Kapat" on the
    /// right (also Esc). `onClose: nil` dismisses.
    func inkSheet(
        _ title: LocalizedStringKey, closeIdentifier: String? = nil, onClose: (() -> Void)? = nil
    ) -> some View {
        modifier(InkSheetModifier(kind: .reading(closeIdentifier: closeIdentifier, onClose: onClose)))
            .inkPageNavigationTitle(title)
    }

    /// Read-only sheet chrome with a non-localized title.
    func inkSheet(
        verbatim title: String, closeIdentifier: String? = nil, onClose: (() -> Void)? = nil
    ) -> some View {
        modifier(InkSheetModifier(kind: .reading(closeIdentifier: closeIdentifier, onClose: onClose)))
            .inkPageNavigationTitle(verbatim: title)
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
        .inkPageNavigationTitle(title)
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
        .inkPageNavigationTitle(verbatim: title)
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
        .inkPageNavigationTitle(title)
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
        content
            .inkPage()
            .inkToggle()
            .presentationBackground(Color.ink.paper)
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
    }
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
}
