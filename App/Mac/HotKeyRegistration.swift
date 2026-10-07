#if os(macOS)
    import Carbon
    import Foundation

    /// Carbon registers a specific combination; it does not monitor other keystrokes.
    @MainActor
    final class HotKeyRegistration {
        private let resources = HotKeyResources()
        private var shortcut: HotKeyShortcut?
        var onPressed: () -> Void = {}

        func register(_ shortcut: HotKeyShortcut) -> Bool {
            guard shortcut.isValid else { return false }
            if self.shortcut == shortcut, resources.hotKey != nil { return true }
            if resources.handler == nil {
                var event = EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
                let status = InstallEventHandler(
                    GetApplicationEventTarget(),
                    { _, event, context in
                        guard let event, let context else { return OSStatus(eventNotHandledErr) }
                        var identifier = EventHotKeyID()
                        guard
                            GetEventParameter(
                                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
                            ) == noErr, identifier.signature == 0x4A72_6E6C, identifier.id == 1
                        else {
                            return OSStatus(eventNotHandledErr)
                        }
                        let registration = Unmanaged<HotKeyRegistration>.fromOpaque(context).takeUnretainedValue()
                        Task { @MainActor [weak registration] in registration?.onPressed() }
                        return noErr
                    }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &resources.handler)
                guard status == noErr else { return false }
            }
            var replacement: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x4A72_6E6C, id: 1),
                GetApplicationEventTarget(), 0, &replacement)
            guard status == noErr, let replacement else { return false }
            if let previous = resources.hotKey { UnregisterEventHotKey(previous) }
            resources.hotKey = replacement
            self.shortcut = shortcut
            return true
        }

        func stop() {
            resources.stop()
            shortcut = nil
        }
    }

    private final class HotKeyResources {
        var hotKey: EventHotKeyRef?
        var handler: EventHandlerRef?

        func stop() {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            if let handler { RemoveEventHandler(handler) }
            hotKey = nil
            handler = nil
        }

        deinit { stop() }
    }
#endif
