import Foundation
import Testing

@testable import VaultIndex

/// The order Diagnostics lists files with unresolved sync versions in.
struct ConflictedFileTests {
    private static let ada = ConflictVersion(modificationTime: 1_791_000_000, deviceName: "Ada'nın Mac'i")
    private static let ece = ConflictVersion(modificationTime: 1_791_000_000, deviceName: "Ece'nin iPhone'u")
    private static let unnamed = ConflictVersion(modificationTime: 1_791_000_000, deviceName: nil)
    private static let older = ConflictVersion(modificationTime: 1_790_000_000, deviceName: "Ada'nın Mac'i")
    private static let unknown = ConflictVersion(modificationTime: 0, deviceName: "Ece'nin iPhone'u")

    @Test func versionsAreNewestFirstThenByDeviceNameWithUnnamedLast() {
        let expected = [Self.ada, Self.ece, Self.unnamed, Self.older, Self.unknown]
        #expect(ConflictVersion.newestFirst(expected) == expected)
        #expect(ConflictVersion.newestFirst(expected.reversed()) == expected)
        #expect(ConflictVersion.newestFirst([Self.unknown, Self.unnamed, Self.older, Self.ece, Self.ada]) == expected)
    }

    @Test func filesAreInPathByteOrderWithSortedVersions() {
        let files = [
            ConflictedFile(path: "people/Mira Tan.md", versions: [Self.older, Self.ada]),
            ConflictedFile(path: "journal/2026-10-02.md", versions: [Self.unknown, Self.ece, Self.unnamed]),
            ConflictedFile(path: "Ada.md", versions: [Self.ada]),
        ]
        #expect(
            ConflictedFile.sorted(files) == [
                ConflictedFile(path: "Ada.md", versions: [Self.ada]),
                ConflictedFile(path: "journal/2026-10-02.md", versions: [Self.ece, Self.unnamed, Self.unknown]),
                ConflictedFile(path: "people/Mira Tan.md", versions: [Self.ada, Self.older]),
            ])
        #expect(ConflictedFile.sorted(files.reversed()) == ConflictedFile.sorted(files))
    }

    /// A decomposed path from disk names the same file as its composed index path.
    @Test func pathIsComposed() {
        let decomposed = "people/Çag\u{0306}la.md".decomposedStringWithCanonicalMapping
        let file = ConflictedFile(path: decomposed, versions: [])
        #expect(Array(file.path.utf8) == Array("people/Çag\u{0306}la.md".precomposedStringWithCanonicalMapping.utf8))
        #expect(file.path.unicodeScalars.count < decomposed.unicodeScalars.count)
    }
}
