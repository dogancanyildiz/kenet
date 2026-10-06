import Foundation
import Testing

@testable import VaultIndex

#if os(macOS)
    import Darwin
#endif

@Test func updatePathsVisitsOnlyNotifiedParentDirectory() throws {
    try withVault { root in
        for directory in 0..<50 {
            for file in 0..<20 {
                try write(root, String(format: "bucket-%02d/note-%02d.md", directory, file), "Su")
            }
        }
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try write(root, "bucket-07/note-03.md", "Kitap")
        let probe = VaultScanner.VisitProbe()
        let result = try VaultScanner.$visitProbe.withValue(probe) {
            try index.update(paths: ["bucket-07/note-03.md"], vaultRoot: root)
        }
        #expect(result.updatedPaths == ["bucket-07/note-03.md"])
        #expect(probe.directories == 1)
        #expect(probe.entries == 20)
        try equivalent(index, root)
    }
}

@Test func updatePathsDropsSubtreeWhenFileParentDirectoryIsMissing() throws {
    try withVault { root in
        try write(root, "notes/Su.md", "Su")
        try write(root, "notes/Kitap.md", "Kitap")
        try write(root, "notes/deep/Spor.md", "Spor")
        try write(root, "journal/2026-10-01.md", "Gun")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes"))
        let result = try index.update(paths: ["notes/Su.md"], vaultRoot: root)
        #expect(Set(result.deletedPaths) == ["notes/Su.md", "notes/Kitap.md", "notes/deep/Spor.md"])
        #expect(try index.files().map(\.path) == ["journal/2026-10-01.md"])
        try equivalent(index, root)
    }
}

@Test func updatePathsForRootFileScansRootShallowly() throws {
    try withVault { root in
        try write(root, "Su.md", "Su")
        try write(root, "notes/Kitap.md", "Kitap")
        try write(root, "notes/deep/Spor.md", "Spor")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try write(root, "Su.md", "Guncel")
        let probe = VaultScanner.VisitProbe()
        let result = try VaultScanner.$visitProbe.withValue(probe) {
            try index.update(paths: ["Su.md"], vaultRoot: root)
        }
        #expect(result.updatedPaths == ["Su.md"])
        #expect(probe.directories == 1)
        // Root listing sees Su.md plus the notes directory entry; it must not descend.
        #expect(probe.entries == 2)
        try equivalent(index, root)
    }
}

@Test func updatePathsRenameAcrossDirectoriesScansBothParents() throws {
    try withVault { root in
        try write(root, "notes/Su.md", "Su")
        try write(root, "notes/Kitap.md", "Kitap")
        try write(root, "archive/Keep.md", "Keep")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("notes/Su.md"),
            to: root.appendingPathComponent("archive/Su.md"))
        let probe = VaultScanner.VisitProbe()
        let result = try VaultScanner.$visitProbe.withValue(probe) {
            try index.update(paths: ["notes/Su.md", "archive/Su.md"], vaultRoot: root)
        }
        #expect(result.deletedPaths == ["notes/Su.md"])
        #expect(result.addedPaths == ["archive/Su.md"])
        #expect(probe.directories == 2)
        try equivalent(index, root)
    }
}

@Test func updatePathsIgnoresTemplatesAndHiddenNotifications() throws {
    try withVault { root in
        try write(root, "notes/Su.md", "Su")
        try write(root, "templates/person.md", "---\ntype: person\n---\n")
        try write(root, ".app/vault.json", "{}\n")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let before = try index.snapshot()
        let probe = VaultScanner.VisitProbe()
        let result = try VaultScanner.$visitProbe.withValue(probe) {
            try index.update(paths: ["templates/person.md", ".app/vault.json"], vaultRoot: root)
        }
        #expect(result.addedPaths.isEmpty && result.updatedPaths.isEmpty && result.deletedPaths.isEmpty)
        #expect(probe.directories == 0)
        #expect(try index.snapshot() == before)
    }
}

@Test func updatePathsCaseOnlyRenameAtRoot() throws {
    try withVault { root in
        try write(root, "Ev.md", "Ev")
        try write(root, "notes/Kitap.md", "Kitap")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("Ev.md"), to: root.appendingPathComponent("ev.md"))
        let result = try index.update(paths: ["Ev.md", "ev.md"], vaultRoot: root)
        #expect(result.deletedPaths == ["Ev.md"])
        #expect(result.addedPaths == ["ev.md"])
        #expect(try index.files().map(\.path) == ["ev.md", "notes/Kitap.md"])
        try equivalent(index, root)
    }
}

#if os(macOS)
    @Test func updatePathsSucceedsWhenOutOfScopeDirectoryIsUnreadable() throws {
        try withVault { root in
            guard geteuid() != 0 else { return }
            try write(root, "notes/Su.md", "Su")
            try write(root, "locked/Secret.md", "Secret")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let locked = root.appendingPathComponent("locked")
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            }
            // macOS may still allow the owner to list a 000 directory; skip when enforcement is absent.
            if (try? FileManager.default.contentsOfDirectory(atPath: locked.path)) != nil { return }
            try write(root, "notes/Su.md", "Guncel")
            var refreshFailed = false
            do { try index.refresh(vaultRoot: root) } catch { refreshFailed = true }
            #expect(refreshFailed)
            let result = try index.update(paths: ["notes/Su.md"], vaultRoot: root)
            #expect(result.updatedPaths == ["notes/Su.md"])
            #expect(try index.files().contains { $0.path == "locked/Secret.md" })
        }
    }
#endif
