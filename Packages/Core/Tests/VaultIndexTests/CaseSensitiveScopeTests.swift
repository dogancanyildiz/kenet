import Foundation
import Testing

@testable import VaultIndex

@Test func scopesCoveringIndexedPathsAddsExactCasedParents() {
    let includes: (String) -> Bool = { path in
        let key = comparisonKey(path)
        return key == "notes" || key.hasPrefix("notes/")
    }
    // Identity spellings: unit-level proof that indexed exact-case parents enter the scope
    // even when the notification only opened `.subtree("notes")`.
    let scopes = scopesCoveringIndexedPaths(
        base: [.subtree("notes")],
        indexedPaths: ["notes/a.md", "Notes/b.md", "journal/keep.md"],
        includes: includes,
        directorySpellings: { [$0] })
    #expect(scopes.contains(.subtree("notes")))
    #expect(scopes.contains(.shallow("notes")))
    #expect(scopes.contains(.shallow("Notes")))
    #expect(!scopes.contains(.shallow("journal")))
}

@Test func scopesCoveringIndexedPathsExpandsComparisonKeySiblingSpellings() {
    let includes: (String) -> Bool = { path in
        comparisonKey(path) == "n/a.md"
    }
    // Only one indexed parent spelling; directorySpellings reports both on-disk variants.
    let scopes = scopesCoveringIndexedPaths(
        base: [.shallow("n")],
        indexedPaths: ["n/a.md"],
        includes: includes,
        directorySpellings: { parent in
            comparisonKey(parent) == "n" ? ["n", "N"] : [parent]
        })
    #expect(scopes.contains(.shallow("n")))
    #expect(scopes.contains(.shallow("N")))
}

@Test func scopesCoveringIndexedPathsRecoversFromMismatchedNotificationSpelling() {
    // Case-sensitive FS: notified "Notes/A.md" is missing → base scope is root shallow,
    // while includes widens to "notes" and would delete every matching indexed path unless
    // their exact-cased parents are added.
    let includes: (String) -> Bool = { path in
        let key = comparisonKey(path)
        return key == "notes" || key.hasPrefix("notes/")
    }
    let scopes = scopesCoveringIndexedPaths(
        base: [.shallow("")],
        indexedPaths: ["notes/a.md", "Notes/b.md"],
        includes: includes,
        directorySpellings: { [$0] })
    #expect(scopes.contains(.shallow("notes")))
    #expect(scopes.contains(.shallow("Notes")))
}

@Test func updatePathsIgnoresHiddenDirectoryEvenWhenNameEndsWithMarkdown() throws {
    try withVault { root in
        try write(root, "a/.x.md/n.md", "Gizli")
        try write(root, "a/visible.md", "Gorunur")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        #expect(try index.files().map(\.path) == ["a/visible.md"])
        let before = try index.snapshot()
        let probe = VaultScanner.VisitProbe()
        let result = try VaultScanner.$visitProbe.withValue(probe) {
            try index.update(paths: ["a/.x.md"], vaultRoot: root)
        }
        #expect(result.addedPaths.isEmpty && result.updatedPaths.isEmpty && result.deletedPaths.isEmpty)
        #expect(probe.directories == 0)
        #expect(try index.snapshot() == before)
        #expect(try index.files().map(\.path) == ["a/visible.md"])
    }
}

@Test func updatePathsPreservesDifferentlyCasedSiblingTreesOnCaseSensitiveFileSystem() throws {
    try withVault { root in
        guard try isCaseSensitiveFileSystem(at: root) else { return }
        try write(root, "notes/a.md", "A")
        try write(root, "Notes/b.md", "B")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        #expect(Set(try index.files().map(\.path)) == ["notes/a.md", "Notes/b.md"])

        let dirUpdate = try index.update(paths: ["notes"], vaultRoot: root)
        #expect(dirUpdate.deletedPaths.isEmpty)
        #expect(Set(try index.files().map(\.path)) == ["notes/a.md", "Notes/b.md"])
        try equivalent(index, root)

        let fileUpdate = try index.update(paths: ["Notes/A.md"], vaultRoot: root)
        #expect(fileUpdate.deletedPaths.isEmpty)
        #expect(Set(try index.files().map(\.path)) == ["notes/a.md", "Notes/b.md"])
        try equivalent(index, root)
    }
}

@Test func updatePathsPreservesDifferentlyCasedFileSpellingsOnCaseSensitiveFileSystem() throws {
    try withVault { root in
        guard try isCaseSensitiveFileSystem(at: root) else { return }
        try write(root, "n/a.md", "a")
        try write(root, "n/A.md", "A")
        try write(root, "N/a.md", "Na")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        #expect(Set(try index.files().map(\.path)) == ["n/a.md", "n/A.md", "N/a.md"])

        let result = try index.update(paths: ["n/a.md"], vaultRoot: root)
        #expect(result.deletedPaths.isEmpty)
        #expect(Set(try index.files().map(\.path)) == ["n/a.md", "n/A.md", "N/a.md"])
        try equivalent(index, root)
    }
}
