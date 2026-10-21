import Foundation
import Testing

/// The built app shares its Documents folder (the default vault) with the Files app and opens
/// documents in place. Where the keys are written is a rule in `SourcePatternRuleTests`; what
/// onboarding and settings say about the vault is measured in `ControlAccessibilityHostedTests`.
struct VaultVisibilityTests {
    @Test func hostInfoPlistContainsGeneratedFileSharingKeys() throws {
        let info = try #require(Self.hostAppInfoDictionary())
        #expect(Self.boolValue(info["LSSupportsOpeningDocumentsInPlace"]) == true)
        #expect(
            Self.boolValue(info["UIFileSharingEnabled"]) == true,
            "UIFileSharingEnabled must be merged into the host Info.plist")
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
}
