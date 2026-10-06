import Foundation
import Testing

@testable import Journal

struct IndexSupportDirectoryTests {
    @Test func prepareExcludesFromBackupAndInvokesProtectionHook() throws {
        let directory = try testDirectory().appendingPathComponent("Indexes", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        var protected: [URL] = []
        try IndexSupportDirectory.prepare(at: directory) { url in
            protected.append(url)
        }
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(protected == [directory])
    }

    @Test func prepareReappliesExclusionOnExistingDirectory() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var directory = root.appendingPathComponent("Indexes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try directory.setResourceValues(values)
        try IndexSupportDirectory.prepare(at: directory) { _ in }
        let updated = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(updated.isExcludedFromBackup == true)
    }
}
