#if os(macOS)
    import AppKit
    import Observation
    import SwiftUI

    @MainActor @Observable
    final class MacQuickEntryController {
        let location: LocationService
        let window: QuickEntryWindowModel
        let shortcut: HotKeySettingsModel
        @ObservationIgnored private let registration: HotKeyRegistration
        @ObservationIgnored private var panel: QuickEntryPanel?
        @ObservationIgnored private var outsideClick: Any?
        @ObservationIgnored private var localInput: Any?
        @ObservationIgnored private var termination: NSObjectProtocol?
        @ObservationIgnored private var started = false

        init(store: IndexStore, location: LocationService) {
            self.location = location
            window = QuickEntryWindowModel(store: store)
            let registration = HotKeyRegistration()
            self.registration = registration
            shortcut = HotKeySettingsModel(register: { registration.register($0) }, pause: { registration.stop() })
            registration.onPressed = { [weak self] in self?.open() }
        }

        func start() async {
            guard !started,
                AppLaunchPolicy.allowsAutomaticStart(
                    environment: ProcessInfo.processInfo.environment, arguments: ProcessInfo.processInfo.arguments)
            else { return }
            started = true
            shortcut.start()
            termination = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
            await window.entry.store.startAutomatically()
        }

        func open() {
            if panel == nil { makePanel() }
            guard let panel else { return }
            window.open()
            window.entry.store.setForeground(true)
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameTopLeftPoint(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - 28))
            }
            panel.makeKeyAndOrderFront(nil)
            installClickMonitors()
            Task { await window.entry.store.refresh() }
        }

        func close() {
            guard window.isPresented else { return }
            window.close()
            removeClickMonitors()
            panel?.orderOut(nil)
            window.entry.store.setForeground(NSApp.isActive)
        }

        private func makePanel() {
            let panel = QuickEntryPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.onDismiss = { [weak self] in self?.close() }
            panel.contentView = NSHostingView(
                rootView: QuickEntryPanelView(
                    model: window,
                    onHeightChange: { [weak self] height in self?.resize(height: height) },
                    onClose: { [weak self] in self?.close() }
                ).environment(location))
            self.panel = panel
        }

        private func resize(height: CGFloat) {
            guard let panel, abs(panel.frame.height - height) > 1 else { return }
            var frame = panel.frame
            frame.origin.y += frame.height - height
            frame.size.height = height
            panel.setFrame(frame, display: true)
        }

        private func installClickMonitors() {
            guard outsideClick == nil else { return }
            outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
            ]) {
                [weak self] _ in
                Task { @MainActor in self?.close() }
            }
            localInput = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
            ) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    if event.type == .keyDown {
                        if event.window === self.panel && event.keyCode == 53 {
                            self.close()
                            return true
                        }
                    } else if event.window !== self.panel {
                        self.close()
                    }
                    return false
                }
                return consumed ? nil : event
            }
        }

        private func removeClickMonitors() {
            if let outsideClick { NSEvent.removeMonitor(outsideClick) }
            if let localInput { NSEvent.removeMonitor(localInput) }
            outsideClick = nil
            localInput = nil
        }

        private func stop() {
            close()
            registration.stop()
            if let termination { NotificationCenter.default.removeObserver(termination) }
            termination = nil
        }
    }
#endif
