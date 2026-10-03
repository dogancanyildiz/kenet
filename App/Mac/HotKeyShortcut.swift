#if os(macOS)
    import Carbon
    import Foundation

    struct HotKeyShortcut: Codable, Equatable, Sendable {
        let keyCode: UInt32
        let modifiers: UInt32
        let keyLabel: String

        static let defaultShortcut = HotKeyShortcut(
            keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), keyLabel: "")

        var isValid: Bool {
            let allowed = UInt32(cmdKey | optionKey | controlKey | shiftKey)
            let required = UInt32(cmdKey | optionKey | controlKey)
            let modifierKeys: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            return keyCode <= 127 && !modifierKeys.contains(keyCode)
                && modifiers & required != 0 && modifiers & ~allowed == 0
                && (keyCode == UInt32(kVK_Space) || !keyLabel.isEmpty)
        }

        var display: String {
            var text = ""
            if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
            return text + (keyCode == UInt32(kVK_Space) ? String(localized: "Boşluk") : keyLabel)
        }
    }
#endif
