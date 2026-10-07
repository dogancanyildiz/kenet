import Foundation
import Testing

/// Locks File Sharing Info.plist keys and the onboarding/settings copy that tell the user
/// where the default vault lives.
struct VaultVisibilityTests {
    @Test func projectYmlEnablesFileSharingKeys() throws {
        let source = try Self.read("project.yml")
        #expect(
            source.contains("INFOPLIST_KEY_UIFileSharingEnabled")
                || source.contains("App/Support/FileSharing.plist"),
            "iOS Documents/Vault must appear in the Files app")
        #expect(
            source.contains("INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace")
                || source.contains("App/Support/FileSharing.plist"),
            "Documents must open in place for Files / Obsidian")
        let plist = try Self.read("App/Support/FileSharing.plist")
        #expect(plist.contains("UIFileSharingEnabled"))
        #expect(plist.contains("LSSupportsOpeningDocumentsInPlace"))
        #expect(plist.contains("<true/>"))
    }

    @Test func hostInfoPlistContainsGeneratedFileSharingKeys() throws {
        let info = try #require(Self.hostAppInfoDictionary())
        #expect(Self.boolValue(info["LSSupportsOpeningDocumentsInPlace"]) == true)
        #expect(
            Self.boolValue(info["UIFileSharingEnabled"]) == true,
            "UIFileSharingEnabled must be merged into the host Info.plist")
    }

    @Test func onboardingDescribesDefaultVaultLocation() throws {
        let source = try Self.read("App/Screens/Onboarding/OnboardingView.swift")
        #expect(source.contains("Yeni kasa oluştur"))
        #expect(
            source.contains("Dosyalar") || source.contains("Vault") || source.contains("Belgeler"),
            "onboarding must say where Create new vault puts files")
    }

    @Test func settingsCanRevealVaultInFinder() throws {
        let source = try Self.read("App/Screens/Settings/VaultSettingsView.swift")
        #expect(source.contains("Finder'da göster") || source.contains("Finder’da göster"))
        #expect(source.contains("activateFileViewerSelecting") || source.contains("NSWorkspace"))
    }

    private static func setting(_ source: String, key: String) -> String? {
        let pattern = #"\#(NSRegularExpression.escapedPattern(for: key)):\s*(\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
            let range = Range(match.range(at: 1), in: source)
        else { return nil }
        return String(source[range])
    }

    /// Unit tests run inside the `.xctest` plug-in; walk up to the host `.app`.
    private static func hostAppInfoDictionary() -> [String: Any]? {
        var url = Bundle.main.bundleURL
        for _ in 0..<6 {
            if url.pathExtension == "app" { return Bundle(url: url)?.infoDictionary }
            url = url.deletingLastPathComponent()
        }
        return Bundle.main.infoDictionary
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool: flag
        case let number as NSNumber: number.boolValue
        case let text as String: ["1", "YES", "true"].contains(text)
        default: nil
        }
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
