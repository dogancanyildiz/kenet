import Foundation
import Testing

/// Guards the settings an App Store Connect upload depends on: the permanent bundle identifier,
/// iPhone-only device family, the export compliance key, the privacy manifest, per-platform
/// entitlements, and that no real team identifier is committed.
struct ReleaseConfigurationTests {
    private static let bundleIdentifier = "com.dogancanyildiz.kenet"
    private static let teamPlaceholder = "XXXXXXXXXX"

    // MARK: - Identity

    @Test func bundleIdentifierIsPermanentAndDefinedOnce() throws {
        let project = try Self.read("project.yml")
        #expect(Self.values(of: "APP_BUNDLE_IDENTIFIER", in: project) == [Self.bundleIdentifier])
        #expect(Self.values(of: "bundleIdPrefix", in: project) == [Self.bundleIdentifier])
        #expect(
            Self.values(of: "PRODUCT_BUNDLE_IDENTIFIER", in: project) == [
                "$(APP_BUNDLE_IDENTIFIER)", "$(APP_BUNDLE_IDENTIFIER).tests", "$(APP_BUNDLE_IDENTIFIER).uitests",
            ])
        // Scripts read the identifier from project.yml instead of repeating it.
        for path in [".github/scripts/record-screen-snapshots.sh", ".github/scripts/screen-tour.sh"] {
            let script = try Self.read(path)
            #expect(script.contains("APP_BUNDLE_IDENTIFIER"), "\(path) must read the identifier from project.yml")
            #expect(!script.contains("com.dravcore"), "\(path) still names the temporary identifier")
            #expect(!script.contains(Self.bundleIdentifier), "\(path) repeats the identifier")
        }
        #expect(!project.contains("com.dravcore"))
    }

    @Test func hostAppCarriesIdentifierNameAndExportCompliance() throws {
        let info = try #require(Self.hostAppInfoDictionary())
        #expect(info["CFBundleIdentifier"] as? String == Self.bundleIdentifier)
        #expect(info["CFBundleDisplayName"] as? String == "Kenet")
        #expect(info["CFBundleName"] as? String == "Kenet")
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    @Test func exportComplianceIsDeclared() throws {
        #expect(
            try Self.values(of: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption", in: Self.read("project.yml")) == ["NO"])
    }

    // MARK: - Device family

    @Test func iOSTargetsIPhoneOnly() throws {
        let project = try Self.read("project.yml")
        #expect(Self.values(of: "TARGETED_DEVICE_FAMILY", in: project) == ["1"])
        #expect(!project.contains("UISupportedInterfaceOrientations_iPad"))
        #expect(!project.contains("UIRequiresFullScreen"))
        #expect(
            Self.values(of: "INFOPLIST_KEY_UISupportedInterfaceOrientations", in: project)
                == ["UIInterfaceOrientationPortrait"])
    }

    // MARK: - Privacy manifest

    @Test func privacyManifestDeclaresNoTrackingAndTheUsedAPICategories() throws {
        let manifest = try Self.plist("App/Resources/PrivacyInfo.xcprivacy")
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String]) == [])
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        #expect(
            try Self.declaredReasons(manifest) == [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
                "NSPrivacyAccessedAPICategoryFileTimestamp": ["3B52.1", "C617.1"],
            ])
    }

    /// A required reason API that appears in the sources without a declaration gets the upload
    /// rejected; one declared without use is noise. Both directions fail here.
    @Test func privacyManifestMatchesRequiredReasonAPIsInSources() throws {
        let patterns: [String: String] = [
            "NSPrivacyAccessedAPICategoryUserDefaults": #"\bUserDefaults\b|@AppStorage\b"#,
            "NSPrivacyAccessedAPICategoryFileTimestamp":
                #"attributesOfItem|[cC]reationDate|[mM]odificationDate|\b[fl]?stat\(|getattrlist"#,
            "NSPrivacyAccessedAPICategoryDiskSpace":
                #"volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|systemSize|statv?fs\("#,
            "NSPrivacyAccessedAPICategorySystemBootTime": #"systemUptime|mach_absolute_time|mach_continuous_time"#,
            "NSPrivacyAccessedAPICategoryActiveKeyboards": #"activeInputModes"#,
        ]
        var sources = ""
        for path in try Self.swiftFiles(under: ["App", "Packages/Core/Sources"]) {
            sources += try Self.read(path) + "\n"
        }
        let used = patterns.filter { sources.range(of: $0.value, options: .regularExpression) != nil }.keys
        let declared = try Self.declaredReasons(Self.plist("App/Resources/PrivacyInfo.xcprivacy")).keys
        #expect(Set(used) == Set(declared))
    }

    // MARK: - Entitlements

    @Test func entitlementsAreSplitByPlatform() throws {
        let project = try Self.read("project.yml")
        #expect(
            Self.values(of: "CODE_SIGN_ENTITLEMENTS", in: project) == [
                "App/Support/Journal-iOS.entitlements", "App/Support/Journal-macOS.entitlements",
            ])
        let iOS = try Self.plist("App/Support/Journal-iOS.entitlements")
        let sandboxKeys = iOS.keys.filter { $0.hasPrefix("com.apple.security.") }
        #expect(sandboxKeys.isEmpty, "macOS sandbox keys in the iOS entitlements: \(sandboxKeys.sorted())")

        let mac = try Self.plist("App/Support/Journal-macOS.entitlements")
        #expect(
            Set(mac.keys) == [
                "com.apple.security.app-sandbox",
                "com.apple.security.files.user-selected.read-write",
                "com.apple.security.personal-information.calendars",
                "com.apple.security.personal-information.location",
            ])
        #expect(mac.values.allSatisfy { $0 as? Bool == true })
    }

    // MARK: - Signing

    @Test func teamIdentifierStaysOutOfTheRepository() throws {
        let ignore = try Self.read(".gitignore").components(separatedBy: .newlines)
        #expect(ignore.contains("Config/Local.xcconfig"), "the local signing file must be ignored")
        #expect(try Self.read("Config/Signing.xcconfig").contains(#"#include? "Local.xcconfig""#))
        #expect(try Self.read("project.yml").contains("Config/Signing.xcconfig"))
        #expect(
            try Self.teamIdentifiers(in: Self.read("Config/Local.xcconfig.example")) == [Self.teamPlaceholder],
            "the example must carry the placeholder")

        var offenders: [String] = []
        for path in try Self.trackedTextFiles() where path != "Config/Local.xcconfig" {
            let real = try Self.teamIdentifiers(in: Self.read(path)).filter { $0 != Self.teamPlaceholder }
            if !real.isEmpty { offenders.append(path) }
        }
        #expect(offenders.isEmpty, "A real team identifier is written in: \(offenders.sorted())")
    }

    @Test func teamIdentifierScanRecognisesAssignments() {
        #expect(Self.teamIdentifiers(in: "DEVELOPMENT_TEAM = AB12CD34EF") == ["AB12CD34EF"])
        #expect(Self.teamIdentifiers(in: "DEVELOPMENT_TEAM: \"AB12CD34EF\"") == ["AB12CD34EF"])
        #expect(Self.teamIdentifiers(in: "DEVELOPMENT_TEAM=\(Self.teamPlaceholder)") == [Self.teamPlaceholder])
        #expect(Self.teamIdentifiers(in: "DEVELOPMENT_TEAM = $(TEAM)").isEmpty)
    }

    // MARK: - Build number

    @Test func buildNumberComesFromGitHistoryAtBuildTime() throws {
        let project = try Self.read("project.yml")
        #expect(project.contains(".github/scripts/build-number.sh"))
        #expect(project.contains("Set :CFBundleVersion $build"))
        #expect(try Self.read(".github/scripts/build-number.sh").contains("rev-list --count HEAD"))
    }

    // MARK: - Reading

    /// Values of `key: value` lines in a YAML source, in file order (quotes stripped).
    private static func values(of key: String, in source: String) -> [String] {
        let pattern = #"(?m)^\s*"?\#(NSRegularExpression.escapedPattern(for: key))"?:[ \t]*(.+?)\s*$"#
        return captures(pattern, in: source).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }

    private static func teamIdentifiers(in source: String) -> [String] {
        captures(#"DEVELOPMENT_TEAM\s*[=:]\s*"?([A-Za-z0-9]{10})\b"#, in: source)
    }

    private static func captures(_ pattern: String, in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    private static func declaredReasons(_ manifest: [String: Any]) throws -> [String: [String]] {
        let entries = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var result: [String: [String]] = [:]
        for entry in entries {
            let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            let reasons = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            #expect(result[category] == nil, "\(category) is declared twice")
            result[category] = reasons.sorted()
        }
        return result
    }

    private static func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent(path))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// Configuration, scripts and documents that are committed; generated and vendored trees are skipped.
    private static func trackedTextFiles() throws -> [String] {
        let extensions: Set<String> = [
            "yml", "yaml", "xcconfig", "example", "sh", "md", "plist", "entitlements", "json",
        ]
        let roots = ["project.yml", "README.md", "AGENTS.md", "Config", ".github", "docs", "App/Support"]
        return try files(under: roots) { extensions.contains($0.pathExtension) }
    }

    private static func swiftFiles(under roots: [String]) throws -> [String] {
        try files(under: roots) { $0.pathExtension == "swift" }
    }

    private static func files(under roots: [String], where include: (URL) -> Bool) throws -> [String] {
        let root = repositoryRoot()
        var result: [String] = []
        for name in roots {
            let url = root.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                result.append(name)
                continue
            }
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                guard include(file) else { continue }
                result.append(file.path.replacingOccurrences(of: root.path + "/", with: ""))
            }
        }
        return result
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
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

    private static func repositoryRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
