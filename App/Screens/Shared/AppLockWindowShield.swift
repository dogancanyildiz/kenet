import SwiftUI

#if os(iOS)
    import UIKit

    /// A scene-local window sits above sheets as well as the navigation root.
    struct AppLockWindowShield: UIViewRepresentable {
        let lock: AppLockService

        func makeUIView(context: Context) -> LockWindowAnchor {
            LockWindowAnchor(lock: lock)
        }

        func updateUIView(_ view: LockWindowAnchor, context: Context) { view.updateCover() }

        static func dismantleUIView(_ view: LockWindowAnchor, coordinator: ()) { view.detach() }
    }

    final class LockWindowAnchor: UIView {
        private let lock: AppLockService
        private var shield: UIWindow?
        private var registration: UUID?

        init(lock: AppLockService) {
            self.lock = lock
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene, shield == nil else { return }
            let shield = UIWindow(windowScene: scene)
            shield.windowLevel = .alert + 1
            shield.rootViewController = UIHostingController(rootView: AppLockCover(lock: lock))
            shield.rootViewController?.view.accessibilityViewIsModal = true
            self.shield = shield
            registration = lock.registerCover { [weak self] in self?.updateCover() }
        }

        func updateCover() {
            guard let shield else { return }
            if lock.shouldCover {
                if shield.isHidden { window?.endEditing(true) }
                shield.isHidden = false
                if lock.isForeground { shield.makeKey() }
            } else {
                let wasKey = shield.isKeyWindow
                shield.isHidden = true
                if wasKey { window?.makeKey() }
            }
        }

        func detach() {
            if let registration { lock.unregisterCover(registration) }
            shield?.isHidden = true
            shield = nil
            registration = nil
        }
    }
#elseif os(macOS)
    import AppKit

    struct AppLockWindowShield: NSViewRepresentable {
        let lock: AppLockService

        func makeNSView(context: Context) -> LockWindowAnchor { LockWindowAnchor(lock: lock) }
        func updateNSView(_ view: LockWindowAnchor, context: Context) { view.updateCover() }
        static func dismantleNSView(_ view: LockWindowAnchor, coordinator: ()) { view.detach() }
    }

    /// Cover the window and any attached sheets without discarding the user's draft.
    final class LockWindowAnchor: NSView {
        private let lock: AppLockService
        private var covers: [NSHostingView<AppLockCover>] = []
        private var registration: UUID?
        private var sheetObserver: NSObjectProtocol?
        private var keyboardMonitor: Any?
        private var hiddenChrome: [ObjectIdentifier: WindowChrome] = [:]

        private struct WindowChrome {
            weak var window: NSWindow?
            let titleVisibility: NSWindow.TitleVisibility
            let toolbarVisible: Bool?
        }

        init(lock: AppLockService) {
            self.lock = lock
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, registration == nil else { return }
            addCover(to: window)
            sheetObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willBeginSheetNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateCover()
                    // AppKit may attach the sheet after sending willBeginSheet.
                    DispatchQueue.main.async { [weak self] in self?.updateCover() }
                }
            }
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.lock.shouldCover,
                        event.window === self.window || event.window?.sheetParent === self.window
                    else { return false }
                    if event.modifierFlags.contains(.command),
                        ["q", "w", "h", "m"].contains(event.charactersIgnoringModifiers ?? "")
                    {
                        return false
                    }
                    if self.lock.isForeground && (event.keyCode == 36 || event.keyCode == 49) {
                        Task { await self.lock.unlock() }
                    }
                    return true
                } ? nil : event
            }
            registration = lock.registerCover { [weak self] in self?.updateCover() }
        }

        private func addCover(to window: NSWindow) {
            guard let content = window.contentView,
                !covers.contains(where: { $0.superview === content })
            else { return }
            let cover = NSHostingView(rootView: AppLockCover(lock: lock))
            cover.frame = content.bounds
            cover.autoresizingMask = [.width, .height]
            cover.setAccessibilityModal(true)
            content.addSubview(cover, positioned: .above, relativeTo: nil)
            covers.append(cover)
        }

        func updateCover() {
            if let sheet = window?.attachedSheet { addCover(to: sheet) }
            for cover in covers {
                cover.isHidden = !lock.shouldCover
                if lock.shouldCover, let window = cover.window {
                    let id = ObjectIdentifier(window)
                    if hiddenChrome[id] == nil {
                        hiddenChrome[id] = WindowChrome(
                            window: window, titleVisibility: window.titleVisibility,
                            toolbarVisible: window.toolbar?.isVisible)
                        window.makeFirstResponder(nil)
                    }
                    // Entity names can also appear in the native title bar.
                    if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
                    if window.toolbar?.isVisible == true { window.toolbar?.isVisible = false }
                }
            }
            if !lock.shouldCover { restoreChrome() }
        }

        private func restoreChrome() {
            for chrome in hiddenChrome.values {
                chrome.window?.titleVisibility = chrome.titleVisibility
                if let visible = chrome.toolbarVisible { chrome.window?.toolbar?.isVisible = visible }
            }
            hiddenChrome = [:]
        }

        func detach() {
            if let registration { lock.unregisterCover(registration) }
            if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) }
            if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
            restoreChrome()
            for cover in covers { cover.removeFromSuperview() }
            covers = []
            registration = nil
            sheetObserver = nil
            keyboardMonitor = nil
        }
    }
#endif
