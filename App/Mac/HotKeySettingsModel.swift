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

        func start(locale: Locale = .current) {
            guard !isRegistered else { return }
            isRegistered = register(shortcut)
            errorText =
                isRegistered
                ? nil
                : PresentationLocalization.string(
                    localized: "Kısayol kaydedilemedi. Başka bir tuş birleşimi dene.", locale: locale)
        }

        func beginRecording() {
            guard !isRecording else { return }
            isRecording = true
            pause()
            isRegistered = false
        }

        func endRecording(locale: Locale = .current) {
            guard isRecording else { return }
            isRecording = false
            start(locale: locale)
        }

        @discardableResult
        func save(locale: Locale = .current) -> Bool {
            guard candidate.isValid else {
                errorText = PresentationLocalization.string(
                    localized: "Kısayolda Control, Option veya Command kullan.", locale: locale)
                return false
            }
            guard register(candidate) else {
                errorText = PresentationLocalization.string(
                    localized: "Kısayol kaydedilemedi. Başka bir tuş birleşimi dene.", locale: locale)
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
