#if os(macOS)
    import AppKit
    import SwiftUI

    final class QuickEntryPanel: NSPanel {
        var onDismiss: () -> Void = {}
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func cancelOperation(_ sender: Any?) { onDismiss() }
        override func resignKey() {
            super.resignKey()
            onDismiss()
        }
    }

    struct QuickEntryPanelView: View {
        let model: QuickEntryWindowModel
        var appLock: AppLockService? = nil
        let onHeightChange: (CGFloat) -> Void
        let onClose: () -> Void
        var onUnlock: () -> Void = {}

        var body: some View {
            ZStack {
                VStack(spacing: 0) {
                    if let status = model.statusText {
                        Text(verbatim: status).font(.caption).foregroundStyle(.secondary).padding()
                    }
                    QuickEntryBar(
                        store: model.entry.store, isEnabled: model.entry.store.canAddEvent,
                        model: model.entry, focusRequest: model.focusRequest)
                }
                .opacity(appLock?.isLocked == true ? 0 : 1)
                .disabled(appLock?.isLocked == true)
                .accessibilityHidden(appLock?.isLocked == true)
                if let appLock, appLock.isLocked {
                    AppLockCover(lock: appLock, allowsBackgroundAuthentication: true)
                        .frame(height: 240)
                }
            }
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeightChange)
            .onChange(of: appLock?.isLocked) { _, locked in
                if locked == false { onUnlock() }
            }
            .onExitCommand(perform: onClose)
        }
    }
#endif
