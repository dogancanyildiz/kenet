import SwiftUI

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

        var isReading: Bool {
            if case .reading = self { return true }
            return false
        }
    }

    let kind: Kind
    /// `false`: the page keeps its manşet title even in a read-only sheet.
    var allowsBarTitle = true

    /// Only a read-only sheet ("Kapat") puts its title in the bar; an editing sheet keeps
    /// "Vazgeç" and the confirm word on the top row and the title below (drawing: Yeni hedef).
    private var titleInBar: Bool { InkSheetChrome.titleInBar && kind.isReading && allowsBarTitle }
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        // A sheet is never a root page (no glow) and its first page has no back item; the pages
        // pushed inside it keep the system bar (``InkPageHeader`` draws no back item there).
        let page =
            content
            .environment(\.inkInSheet, true)
            .environment(\.inkHeaderBackTitle, nil)
            .environment(\.inkBackTitle, nil)
            .environment(\.inkPageGlow, false)
            .environment(\.inkSheetBarTitle, titleInBar)
            .environment(\.inkHeadlineTitleInBar, titleInBar)
            .inkPage()
            .inkToggle()
            .presentationBackground(Color.ink.elevated)
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
                // Drawing: a visible grabber and the sheet's large corner radius.
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(InkCorner.xl)
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
struct InkSheetCancelItem: ToolbarContent {
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
struct InkSheetButtonStyle: ButtonStyle {
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
    /// Esc / Return on sheets. On iOS the shortcut only fires from a hardware keyboard (iPad);
    /// touch behavior stays the system's toolbar placements.
    func inkSheetShortcut(_ shortcut: KeyboardShortcut) -> some View {
        keyboardShortcut(shortcut)
    }
}
