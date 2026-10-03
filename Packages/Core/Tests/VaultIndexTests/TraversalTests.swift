import Foundation
import Testing

@testable import VaultIndex

@Test func symbolicFilesAndDirectoriesAreReportedWithoutFollowing() throws {
    try withVault { root in
        try write(root, "notes/Su.md", "Su")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Kitap.md"),
            withDestinationURL: root.appendingPathComponent("notes/Su.md"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("people"),
            withDestinationURL: root.appendingPathComponent("notes"))
        let index = try VaultIndex()
        let result = try index.rebuild(vaultRoot: root)
        #expect(
            result.skippedPaths == [
                SkippedPath(path: "Kitap.md", reason: .symbolicLink),
                SkippedPath(path: "people", reason: .symbolicLink),
            ])
        #expect(try index.files().map(\.path) == ["notes/Su.md"])
        #expect(try index.search("Su").count == 1)
    }
}

@Test func duplicateNormalizedPathsKeepFirstPhysicalByteSpelling() throws {
    try withVault { root in
        let composed = "Çınaraltı Kafe.md"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let nfcURL = root.appendingPathComponent(composed)
        let nfdURL = root.appendingPathComponent(decomposed)
        try Data("Kitap".utf8).write(to: nfcURL)
        try Data("Su".utf8).write(to: nfdURL)
        let physical = try FileManager.default.contentsOfDirectory(atPath: root.path)
        if physical.count == 2 {
            try write(root, "Spor.md", "Spor")
            let index = try VaultIndex()
            let result = try index.rebuild(vaultRoot: root)
            #expect(result.skippedPaths.count == 1)
            #expect(Array(result.skippedPaths[0].path.utf8) == Array(composed.utf8))
            #expect(result.skippedPaths[0].reason == .duplicateNormalizedPath)
            #expect(try index.files().count == 2)
            #expect(try index.search("Su").count == 1)
            #expect(try index.search("Kitap").isEmpty)
        }
        // Canonically insensitive filesystems cannot store both spellings; verify the scanner's
        // selection with explicit physical spellings too, without relying on filesystem equality.
        let candidates = [
            ScannedFile(url: nfcURL, path: composed, physicalPath: composed),
            ScannedFile(url: nfdURL, path: composed, physicalPath: decomposed),
            ScannedFile(url: root.appendingPathComponent("Spor.md"), path: "Spor.md", physicalPath: "Spor.md"),
        ]
        for ordered in [candidates, Array(candidates.reversed())] {
            var skipped: [SkippedPath] = []
            let files = VaultScanner.deduplicate(ordered, skipped: &skipped)
            #expect(files.count == 2)
            #expect(Array(files.first { $0.path == composed }!.physicalPath.utf8) == Array(decomposed.utf8))
            #expect(skipped.count == 1 && skipped[0].reason == .duplicateNormalizedPath)
            #expect(Array(skipped[0].path.utf8) == Array(composed.utf8))
        }
    }
}
