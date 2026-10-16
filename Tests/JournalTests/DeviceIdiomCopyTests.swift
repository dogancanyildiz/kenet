import SwiftUI
import Testing

@testable import Journal

/// Copy and keyboard gates that follow the device kind (never the layout).
struct DeviceIdiomCopyTests {
    /// Resolves a catalog key from the Turkish or English table, whatever the process language.
    private func text(_ resource: LocalizedStringResource, language: String) throws -> String {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        return bundle.localizedString(forKey: resource.key, value: nil, table: nil)
    }

    @Test func tipNamesOnlyThePathsTheDeviceHas() throws {
        let phone = try text(EntryPointPlatform.tip(for: .phone), language: "tr")
        let pad = try text(EntryPointPlatform.tip(for: .pad), language: "tr")
        let mac = try text(EntryPointPlatform.tip(for: .mac), language: "tr")
        #expect(phone == "Siri, Kısayollar ve Eylem düğmesiyle de yazabilirsin.")
        #expect(pad == "Siri ve Kısayollar ile de yazabilirsin.")
        #expect(mac == "Siri, Kısayollar ve klavye kısayoluyla da yazabilirsin.")
        #expect(!pad.contains("Eylem"))
        let padEnglish = try text(EntryPointPlatform.tip(for: .pad), language: "en")
        #expect(padEnglish == "You can also write with Siri and Shortcuts.")
        #expect(!padEnglish.contains("Action"))
    }

    @Test func newVaultHintNamesTheDevicesOwnFilesLocation() throws {
        let phone = try text(OnboardingCopy.newVaultLocation(for: .phone), language: "tr")
        let pad = try text(OnboardingCopy.newVaultLocation(for: .pad), language: "tr")
        #expect(phone.contains("iPhone’umda"))
        #expect(pad.contains("iPad’imde"))
        #expect(!pad.contains("iPhone"))
        let padEnglish = try text(OnboardingCopy.newVaultLocation(for: .pad), language: "en")
        #expect(padEnglish.contains("On My iPad"))
        #expect(!padEnglish.contains("iPhone"))
        let mac = try text(OnboardingCopy.newVaultLocation(for: .mac), language: "tr")
        #expect(mac.contains("Belgeler"))
    }

    @Test func currentIdiomMatchesThePlatform() async {
        let current = await MainActor.run { DeviceIdiom.current }
        #if os(macOS)
            #expect(current == .mac)
        #else
            #expect(current == .phone || current == .pad)
        #endif
    }

    /// The menu bar and the quick-entry box read this table: a change here moves both.
    @Test func shortcutTableIsTheDocumentedOne() {
        let table = JournalShortcut.allCases.map { shortcut -> String in
            let flags = shortcut.modifiers
            let shift = flags.contains(.shift) ? "⇧" : ""
            let command = flags.contains(.command) ? "⌘" : ""
            return "\(command)\(shift)\(shortcut.key.character)"
        }
        #expect(table == ["⌘f", "⌘k", "⌘t", "⌘⇧t"])
    }
}
