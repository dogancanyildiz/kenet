import Foundation
import Testing

@testable import Journal

/// Runs every `Fixtures/import/<case>/` vault through scan + prepare and compares the tree,
/// file bytes, and report/result summary to the portable expectations.
@MainActor struct VaultImportFixtureTests {
    struct Case: Decodable {
        struct Options: Decodable {
            var folders: Bool
            var settings: Bool
            var types: Bool
        }
        struct Candidate: Decodable, Equatable {
            var path: String
            var kind: String
        }
        struct Report: Decodable {
            var missingFolders: [String]
            var caseVariantFolders: [String]
            var missingTemplates: [String]
            var needsSettings: Bool
            var canPrepare: Bool
            var markdownCount: Int
            var journalDays: [String]
            var externalDays: [String]
            var typed: [String: Int]
            var candidates: [Candidate]
            var skipped: [String]
        }
        struct Result: Decodable {
            var created: [String]
            var typed: [String]
            var skipped: [String]
            var failures: [String]
        }

        var options: Options
        var apply: Bool
        var emptyBefore: Bool?
        var report: Report
        var result: Result
        var expectedDirectories: [String]
        var generatedTemplates: [String: String]
    }

    @Test(arguments: [
        "empty",
        "obsidian-days-only",
        "untyped-entities",
        "already-prepared",
        "case-variant-journal",
        "unreadable-frontmatter",
        "newer-format-version",
    ])
    func portableFixtures(_ name: String) async throws {
        let folder = try fixturesRoot().appendingPathComponent("import/" + name)
        let spec = try JSONDecoder().decode(
            Case.self, from: Data(contentsOf: folder.appendingPathComponent("case.json")))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vault-import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let before = folder.appendingPathComponent("before")
        if spec.emptyBefore != true, FileManager.default.fileExists(atPath: before.path) {
            for item in try FileManager.default.contentsOfDirectory(
                at: before, includingPropertiesForKeys: nil)
            {
                try FileManager.default.copyItem(
                    at: item, to: root.appendingPathComponent(item.lastPathComponent))
            }
        }

        let report = try VaultImportScanner.inspect(root)
        #expect(report.missingFolders == spec.report.missingFolders)
        #expect(report.caseVariantFolders == spec.report.caseVariantFolders)
        #expect(report.missingTemplates == spec.report.missingTemplates)
        #expect(report.needsSettings == spec.report.needsSettings)
        #expect(report.canPrepare == spec.report.canPrepare)
        #expect(report.markdownCount == spec.report.markdownCount)
        #expect(report.journalDays == spec.report.journalDays)
        #expect(report.externalDays == spec.report.externalDays)
        #expect(report.typed == spec.report.typed)
        #expect(
            report.candidates.map { Case.Candidate(path: $0.path, kind: $0.kind) }
                == spec.report.candidates)
        #expect(report.skipped == spec.report.skipped)

        guard spec.apply else { return }

        let options = VaultImportOptions(
            folders: spec.options.folders, settings: spec.options.settings,
            types: spec.options.types)
        let result = await VaultImportWriter.apply(report: report, options: options)
        #expect(result.created == spec.result.created)
        #expect(result.typed == spec.result.typed)
        #expect(result.skipped == spec.result.skipped)
        #expect(result.failures == spec.result.failures)

        for directory in spec.expectedDirectories {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(directory).path, isDirectory: &isDirectory)
            #expect(exists && isDirectory.boolValue, "missing directory \(directory)")
        }

        let expectedRoot = folder.appendingPathComponent("expected")
        let expectedFiles = try regularFiles(under: expectedRoot)
        let actualFiles = try regularFiles(under: root)
        #expect(actualFiles.keys.sorted() == expectedFiles.keys.sorted())

        for path in expectedFiles.keys.sorted() {
            let expected: Data
            if let kind = spec.generatedTemplates[path] {
                expected = try VaultImportBootstrap.template(kind)
            } else {
                expected = expectedFiles[path]!
            }
            #expect(actualFiles[path] == expected, "\(name): \(path)")
        }
    }

    private func fixturesRoot(sourcePath: String = #filePath) throws -> URL {
        if let override = ProcessInfo.processInfo.environment["FIXTURES_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        var directory = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        while true {
            let candidate = directory.appendingPathComponent("Fixtures", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                return candidate
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                Issue.record("Fixtures directory not found above \(sourcePath)")
                throw CocoaError(.fileNoSuchFile)
            }
            directory = parent
        }
    }

    private func regularFiles(under root: URL) throws -> [String: Data] {
        let root = root.resolvingSymlinksInPath()
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [:] }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            let path = url.resolvingSymlinksInPath().path
            let relative = String(path.dropFirst(root.path.count + (root.path.hasSuffix("/") ? 0 : 1)))
            result[relative] = try Data(contentsOf: url)
        }
        return result
    }
}
