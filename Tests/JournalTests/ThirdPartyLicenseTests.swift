import Foundation
import Testing

@testable import Journal

/// Every package that ships in the app is named in the license notice, with the unmodified
/// LICENSE file bundled beside it. Test-target packages are read from `project.yml` and left out.
/// `Package.resolved` also lists transitive pins of the test package (the lockfile has no
/// dependency edges); those URLs are not declared by the app or by Core, so they are not attributed.
struct ThirdPartyLicenseTests {
    @Test func everyShippingPackageIsNamedWithItsLicenseText() throws {
        let pins = try Self.resolvedPins()
        let project = try Self.manifest(from: Self.read("project.yml"))
        let shippingURLs = try Self.shippingPackageURLs(project)
        let excludedURLs = Self.testOnlyPackageURLs(project)
        let shipping = pins.filter { Self.matches($0.location, shippingURLs) }.map(\.identity)
        let excluded = pins.filter { Self.matches($0.location, excludedURLs) }.map(\.identity)

        #expect(!shipping.isEmpty, "no shipping package resolved from project.yml and Package.swift")
        #expect(
            !excluded.isEmpty,
            "project.yml test-target dependencies did not match a resolved package")
        #expect(Set(shipping).isDisjoint(with: Set(excluded)))

        let notices = ThirdPartyNotices.sources
        let noticeNames = Set(notices.map { $0.name.lowercased() })
        #expect(
            noticeNames == Set(shipping.map { $0.lowercased() }),
            "notice \(noticeNames.sorted()) vs shipping \(shipping.sorted()); test-only \(excluded.sorted())")

        let bundle = ThirdPartyNotices.applicationBundle()
        for source in notices {
            let bundled = ThirdPartyNotices.text(for: source, in: bundle)
            let relative = "App/Resources/\(source.resourceName).\(source.resourceExtension)"
            let repo = try Self.read(relative)
            #expect(!bundled.isEmpty, "\(source.name) license is not in the app bundle")
            #expect(bundled == repo, "\(source.name) bundled license differs from \(relative)")
        }
    }

    // MARK: - Lockfile and project

    private struct Pin: Decodable {
        let identity: String
        let location: String
    }

    private struct Resolved: Decodable {
        let pins: [Pin]
    }

    private struct PackageSpec {
        var url: String?
        var path: String?
    }

    private struct TargetSpec {
        var type = ""
        var packages: [String] = []
    }

    private struct ProjectManifest {
        var packages: [String: PackageSpec] = [:]
        var targets: [TargetSpec] = []
    }

    private static func resolvedPins() throws -> [Pin] {
        let data = Data(try read("Packages/Core/Package.resolved").utf8)
        return try JSONDecoder().decode(Resolved.self, from: data).pins
    }

    /// Remote URLs the application target links: its own package URLs, plus `.package(url:)`
    /// declarations of the local packages it depends on.
    private static func shippingPackageURLs(_ project: ProjectManifest) throws -> [String] {
        var urls: [String] = []
        for target in project.targets where target.type == "application" {
            for name in Set(target.packages) {
                guard let spec = project.packages[name] else { continue }
                if let url = spec.url { urls.append(url) }
                if let path = spec.path {
                    urls.append(contentsOf: packageURLs(in: try read(path + "/Package.swift")))
                }
            }
        }
        return urls
    }

    /// Package URLs referenced by a test target and not by the application.
    private static func testOnlyPackageURLs(_ project: ProjectManifest) -> [String] {
        let testTypes: Set<String> = ["bundle.unit-test", "bundle.ui-testing"]
        let appPackages = Set(project.targets.filter { $0.type == "application" }.flatMap(\.packages))
        let testPackages = Set(
            project.targets.filter { testTypes.contains($0.type) }.flatMap(\.packages))
        return testPackages.subtracting(appPackages).compactMap { project.packages[$0]?.url }
    }

    private static func packageURLs(in manifest: String) -> [String] {
        let pattern = #"\.package\(\s*url:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: manifest, range: NSRange(manifest.startIndex..., in: manifest)).compactMap {
            Range($0.range(at: 1), in: manifest).map { String(manifest[$0]) }
        }
    }

    private static func matches(_ location: String, _ urls: [String]) -> Bool {
        let canonical = canonicalPackageURL(location)
        return urls.contains { canonicalPackageURL($0) == canonical }
    }

    private static func canonicalPackageURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix(".git") { value.removeLast(4) }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private static func manifest(from source: String) -> ProjectManifest {
        var project = ProjectManifest()
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if indent(of: lines[index]) == 0, trimmed == "packages:" {
                index = parsePackages(lines, from: index + 1, into: &project)
            } else if indent(of: lines[index]) == 0, trimmed == "targets:" {
                index = parseTargets(lines, from: index + 1, into: &project)
            } else {
                index += 1
            }
        }
        return project
    }

    private static func parsePackages(
        _ lines: [String], from start: Int, into project: inout ProjectManifest
    ) -> Int {
        var index = start
        var current: String?
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            let level = indent(of: line)
            if level == 0 { return index }
            if level == 2, trimmed.hasSuffix(":") {
                let name = String(trimmed.dropLast())
                current = name
                project.packages[name] = PackageSpec()
                index += 1
                continue
            }
            if let name = current, level >= 4 {
                if let url = scalar("url", in: trimmed) {
                    project.packages[name]?.url = url
                } else if let path = scalar("path", in: trimmed) {
                    project.packages[name]?.path = path
                }
            }
            index += 1
        }
        return index
    }

    private static func parseTargets(
        _ lines: [String], from start: Int, into project: inout ProjectManifest
    ) -> Int {
        var index = start
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            let level = indent(of: line)
            if level == 0 { return index }
            if level == 2, trimmed.hasSuffix(":") {
                var target = TargetSpec()
                index = parseTargetBody(lines, from: index + 1, into: &target)
                project.targets.append(target)
                continue
            }
            index += 1
        }
        return index
    }

    private static func parseTargetBody(
        _ lines: [String], from start: Int, into target: inout TargetSpec
    ) -> Int {
        var index = start
        var inDependencies = false
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            let level = indent(of: line)
            if level <= 2 { return index }
            if level == 4, let type = scalar("type", in: trimmed) {
                target.type = type
                inDependencies = false
            } else if level == 4, trimmed == "dependencies:" {
                inDependencies = true
            } else if level == 4 {
                inDependencies = false
            } else if inDependencies, trimmed.hasPrefix("- package:") {
                let name = unquote(trimmed.dropFirst("- package:".count).trimmingCharacters(in: .whitespaces))
                target.packages.append(name)
            }
            index += 1
        }
        return index
    }

    private static func scalar(_ key: String, in trimmed: String) -> String? {
        let prefix = key + ":"
        guard trimmed.hasPrefix(prefix) else { return nil }
        return unquote(trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
    }

    private static func unquote(_ value: some StringProtocol) -> String {
        var text = String(value)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }

    private static func indent(of line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private static func repositoryRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
