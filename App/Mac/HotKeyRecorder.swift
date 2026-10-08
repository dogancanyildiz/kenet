#if os(macOS)
    import AppKit
    import Carbon
    import SwiftUI

    struct HotKeyRecorder: NSViewRepresentable {
        @Binding var candidate: HotKeyShortcut
        let onBegin: () -> Void
        let onEnd: () -> Void

        func makeNSView(context: Context) -> RecorderView { RecorderView() }
        func updateNSView(_ view: RecorderView, context: Context) {
            view.shortcut = candidate
            view.onRecord = { candidate = $0 }
            view.onBegin = onBegin
            view.onEnd = onEnd
            view.needsDisplay = true
        }

        final class RecorderView: NSView {
            var shortcut = HotKeyShortcut.defaultShortcut
            var onRecord: (HotKeyShortcut) -> Void = { _ in }
            var onBegin: () -> Void = {}
            var onEnd: () -> Void = {}
            private var recording = false
            override var acceptsFirstResponder: Bool { true }
            override var intrinsicContentSize: NSSize { NSSize(width: 300, height: 40) }

            override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
            override func becomeFirstResponder() -> Bool {
                recording = true
                onBegin()
                needsDisplay = true
                return true
            }
            override func resignFirstResponder() -> Bool {
                recording = false
                onEnd()
                needsDisplay = true
                return true
            }

            override func accessibilityPerformPress() -> Bool { window?.makeFirstResponder(self) ?? false }

            override func performKeyEquivalent(with event: NSEvent) -> Bool {
                guard recording else { return false }
                keyDown(with: event)
                return true
            }

            override func keyDown(with event: NSEvent) {
                if event.keyCode == UInt16(kVK_Escape) {
                    window?.makeFirstResponder(nil)
                    return
                }
                var modifiers: UInt32 = 0
                if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
                if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
                if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
                if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
                let keyCode = UInt32(event.keyCode)
                let label = Self.labels[keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
                onRecord(HotKeyShortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: label))
                window?.makeFirstResponder(nil)
            }

            override func draw(_ dirtyRect: NSRect) {
                let cornerRadius = InkSize.kanbanCorner
                let border = NSBezierPath(
                    roundedRect: bounds.insetBy(dx: 1, dy: 1),
                    xRadius: cornerRadius,
                    yRadius: cornerRadius)
                NSColor(Color.ink.well).setFill()
                border.fill()

                let strokeColor = recording ? NSColor(Color.ink.accent) : NSColor(Color.ink.control)
                strokeColor.setStroke()
                border.lineWidth = recording ? 2 : InkStroke.control
                border.stroke()

                let title = recording ? String(localized: "Bir tuş birleşimine bas…") : shortcut.display
                let textColor = recording ? NSColor(Color.ink.secondaryText) : NSColor(Color.ink.text)
                (title as NSString).draw(
                    at: NSPoint(x: 12, y: 12),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: textColor,
                    ])
                setAccessibilityLabel(String(localized: "Hızlı giriş kısayolu"))
                setAccessibilityValue(title)
                setAccessibilityRole(.button)
            }

            private static let labels: [UInt32: String] = [
                36: "↩", 48: "⇥", 51: "⌫", 76: "⌤", 117: "⌦", 115: "↖", 119: "↘",
                116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
                122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
                100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14",
                113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
            ]
        }
    }
#endif
