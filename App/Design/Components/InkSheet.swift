import SwiftUI

/// The single confirm word of an editing sheet.
enum InkSheetConfirmation: Equatable, Sendable {
    /// "Kaydet": the sheet changes an existing record.
    case save
    /// "Oluştur": the sheet opens a new record.
    case create
    /// "Taşı": the sheet moves an existing item to another location.
    case move

    /// String Catalog key.
    var catalogKey: String {
        switch self {
        case .save: "Kaydet"
        case .create: "Oluştur"
        case .move: "Taşı"
        }
    }
}

/// Pure rules for the sheet toolbar (unit-tested; ``InkSheetModifier`` calls these).
enum InkSheetChrome {
    enum Button: Equatable, Sendable {
        /// Left, editing sheet: "Vazgeç".
        case cancel
        /// Right, editing sheet: "Kaydet" / "Oluştur" / "Taşı".
        case confirm
        /// Right, read-only sheet: "Kapat".
        case close
    }

    /// String Catalog keys, defined once for every sheet. "Bitti" is not used.
    static let cancelKey = "Vazgeç"
    static let closeKey = "Kapat"

    /// iOS: the sheet's title is an inline large title in the system bar, on the row of
    /// "Kapat" / "Vazgeç" (drawing: Ayarlar). Mac keeps the manşet in the page.
    #if os(iOS)
        static let titleInBar = true
    #else
        static let titleInBar = false
    #endif

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
    ///   - confirm: `.save` ("Kaydet"), `.create` ("Oluştur") or `.move` ("Taşı").
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
            .inkSheetNavigationTitle(title, titleInBar: true)
    }

    /// Read-only sheet chrome with a non-localized title. `titleInBar: false` keeps the title
    /// in the page under "Kapat": a long user title (a calendar event's) would meet the word.
    func inkSheet(
        verbatim title: String, closeIdentifier: String? = nil, onClose: (() -> Void)? = nil,
        titleInBar: Bool = true
    ) -> some View {
        modifier(
            InkSheetModifier(
                kind: .reading(closeIdentifier: closeIdentifier, onClose: onClose), allowsBarTitle: titleInBar)
        )
        .inkSheetNavigationTitle(verbatim: title, titleInBar: titleInBar)
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
        // A byline keeps the title in the page (drawing: Günü kapat, "Adım 1/3" under it).
        .modifier(InkSheetModifier(kind: kind, allowsBarTitle: byline == nil))
        .inkSheetNavigationTitle(title, titleInBar: kind.isReading && byline == nil)
    }
}

extension View {
    /// Sheet navigation title: on iPhone the system bar title is set then hidden (back history).
    /// On Mac the sans title must be an explicit blank: leaving it unset lets the stack infer the
    /// manşet text into the toolbar; the default title item is also removed.
    @ViewBuilder func inkSheetNavigationTitle(
        _ title: LocalizedStringKey, titleInBar: Bool = false
    ) -> some View {
        #if os(macOS)
            navigationTitle(" ")
                .toolbar(removing: .title)
        #else
            if titleInBar {
                inkSheetBarNavigationTitle(title)
            } else {
                inkPageNavigationTitle(title)
            }
        #endif
    }

    @ViewBuilder func inkSheetNavigationTitle(
        verbatim title: String, titleInBar: Bool = false
    ) -> some View {
        #if os(macOS)
            navigationTitle(" ")
                .toolbar(removing: .title)
        #else
            if titleInBar {
                inkSheetBarNavigationTitle(verbatim: title)
            } else {
                inkPageNavigationTitle(verbatim: title)
            }
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
