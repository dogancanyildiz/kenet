#if os(macOS)
    import Foundation
    import Observation

    @MainActor @Observable
    final class HotKeySettingsModel {
        private(set) var shortcut: HotKeyShortcut
        var candidate: HotKeyShortcut
        private(set) var errorText: String?
        private(set) var isRegistered = false
        private(set) var isRecording = false
        @ObservationIgnored private let defaults: UserDefaults
        @ObservationIgnored private let register: (HotKeyShortcut) -> Bool
        @ObservationIgnored private let pause: () -> Void
        private static let defaultsKey = "mac.quickEntryShortcut"

        init(
            defaults: UserDefaults = .standard, register: @escaping (HotKeyShortcut) -> Bool,
            pause: @escaping () -> Void = {}
        ) {
            self.defaults = defaults
            self.register = register
            self.pause = pause
            let stored = defaults.data(forKey: Self.defaultsKey).flatMap {
                try? JSONDecoder().decode(HotKeyShortcut.self, from: $0)
            }
            let initial = stored.flatMap { $0.isValid ? $0 : nil } ?? .defaultShortcut
            shortcut = initial
            candidate = initial
        }

        func start() {
            guard !isRegistered else { return }
            isRegistered = register(shortcut)
            errorText = isRegistered ? nil : String(localized: "Kısayol kaydedilemedi. Başka bir tuş birleşimi dene.")
        }

        func beginRecording() {
            guard !isRecording else { return }
            isRecording = true
            pause()
            isRegistered = false
        }

        func endRecording() {
            guard isRecording else { return }
            isRecording = false
            start()
        }

        @discardableResult
        func save() -> Bool {
            guard candidate.isValid else {
                errorText = String(localized: "Kısayolda Control, Option veya Command kullan.")
                return false
            }
            guard register(candidate) else {
                errorText = String(localized: "Kısayol kaydedilemedi. Başka bir tuş birleşimi dene.")
                return false
            }
            shortcut = candidate
            isRegistered = true
            defaults.set(try? JSONEncoder().encode(shortcut), forKey: Self.defaultsKey)
            errorText = nil
            return true
        }
    }
#endif
