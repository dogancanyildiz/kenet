import Foundation
import Testing

@testable import VaultIndex

private func temporaryRootSpellings() -> [String] {
    #if os(macOS)
        let temporary = FileManager.default.temporaryDirectory.path
        let publicPath = temporary.hasPrefix("/private/") ? String(temporary.dropFirst(8)) : temporary
        return ["/private" + publicPath, publicPath, "/private/tmp", "/tmp"]
    #else
        return [FileManager.default.temporaryDirectory.path]
    #endif
}

@Test(arguments: temporaryRootSpellings())
func deletedNotificationsUseTheSameRootIdentity(_ directory: String) throws {
    try withVault(in: URL(fileURLWithPath: directory)) { root in
        #expect(root.path.hasPrefix(directory + "/"))
        #if os(macOS)
            let alternatePath =
                root.path.hasPrefix("/private/") ? String(root.path.dropFirst(8)) : "/private" + root.path
            let alternate = URL(fileURLWithPath: alternatePath)
        #else
            let alternate = root
        #endif
        try write(root, "notes/Su.md", "Su")
        try write(root, "notes/Kitap.md", "Kitap")
        try write(root, "notes/deep/inner/Spor.md", "Spor")
        try write(root, "notes/deep/Kitap.md", "Kitap")
        try write(root, "journal/2026-10-01.md", "## Events\n- [[Su]] [[Kitap]] [[Spor]] [[Ev]]")
        let index = try VaultIndex()
        let counterpart = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try counterpart.rebuild(vaultRoot: alternate)
        func check() throws {
            #expect(try index.snapshot() == counterpart.snapshot())
            try equivalent(index, root)
            try equivalent(counterpart, alternate)
        }
        try check()

        // Relative file notification whose leaf no longer exists.
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes/Su.md"))
        let relative = try index.update(paths: ["notes/Su.md"], vaultRoot: root)
        #expect(relative.deletedPaths == ["notes/Su.md"])
        #expect(try counterpart.update(paths: ["notes/Su.md"], vaultRoot: alternate) == relative)
        try check()

        // Absolute file notification, using both physical root spellings.
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes/Kitap.md"))
        let absolute = try index.update(paths: [root.appendingPathComponent("notes/Kitap.md").path], vaultRoot: root)
        #expect(absolute.deletedPaths == ["notes/Kitap.md"])
        #expect(
            try counterpart.update(
                paths: [alternate.appendingPathComponent("notes/Kitap.md").path], vaultRoot: alternate) == absolute)
        try check()

        // The old name is absent when the rename notification arrives.
        let old = "notes/deep/inner/Spor.md"
        let new = "notes/deep/inner/Ev.md"
        try FileManager.default.moveItem(at: root.appendingPathComponent(old), to: root.appendingPathComponent(new))
        let rename = try index.update(paths: [root.appendingPathComponent(old).path, new], vaultRoot: root)
        #expect(rename.deletedPaths == [old] && rename.addedPaths == [new])
        #expect(
            try counterpart.update(paths: [alternate.appendingPathComponent(old).path, new], vaultRoot: alternate)
                == rename)
        try check()

        // Several absent directory components must be appended to the surviving root.
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes"))
        let deletedDirectory = "notes/deep"
        let removal = try index.update(paths: [root.appendingPathComponent(deletedDirectory).path], vaultRoot: root)
        #expect(removal.deletedPaths == ["notes/deep/Kitap.md", new])
        #expect(
            try counterpart.update(
                paths: [alternate.appendingPathComponent(deletedDirectory).path], vaultRoot: alternate) == removal)
        try check()
    }
}

@Test func deletedNotificationResolvesExistingSymlinkAncestor() throws {
    try withVault { root in
        let real = root.appendingPathComponent("sample")
        let alias = root.appendingPathComponent("alias")
        try write(real, "notes/deep/Su.md", "Su")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: real)
        try FileManager.default.removeItem(at: real.appendingPathComponent("notes"))
        let result = try index.update(paths: [alias.appendingPathComponent("notes/deep").path], vaultRoot: real)
        #expect(result.deletedPaths == ["notes/deep/Su.md"])
        try equivalent(index, real)
    }
}
