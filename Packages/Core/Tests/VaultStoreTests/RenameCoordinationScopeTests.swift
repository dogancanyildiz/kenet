import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

/// After the move, a rename claims only the files its update pass can change or report: the files
/// linking to the renamed one, and a file whose raw frontmatter field names it. Every other file of
/// the vault is left unclaimed (each claim costs a coordinator round trip on a large vault).
struct RenameCoordinationScopeTests {
    private static let person = "people/Zora Kurgu.md"
    private static let renamed = "people/Zora Yeni.md"

    @Test func onlyLinkSourcesAndRawFieldMentionsAreClaimed() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(Self.person, "---\ntype: person\nname: Zora Kurgu\n---\n")
        try vault.write("people/Luma Kurgu.md", "---\ntype: person\nname: Luma Kurgu\n---\n")
        for number in 0..<40 {
            let link = number.isMultiple(of: 8) ? "[[Zora Kurgu]]" : "[[Luma Kurgu]]"
            try vault.write("notes/Sayfa \(number).md", "Kurgu satır \(link)\n")
        }
        // Raw fields have no link rows: only the one naming Zora is reported, so only it is claimed.
        try vault.write("notes/Ham Zora.md", "---\nraw: |\n  [[Zora Kurgu]]\n---\nGövde.\n")
        try vault.write("notes/Ham Luma.md", "---\nraw: |\n  [[Luma Kurgu]]\n---\nGövde.\n")
        try Data([0x5B, 0x5B, 0x5A, 0x0A, 0xFF]).write(to: vault.root.appendingPathComponent("notes/Bozuk.md"))
        try vault.index.rebuild(vaultRoot: vault.root)
        let before = try Self.contents(of: vault)
        let claims = ClaimLog()
        let store = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: claims)

        let result = try await store.renamingEntity(at: Self.person, to: "Zora Yeni")

        let linking = (0..<40).filter { $0.isMultiple(of: 8) }.map { "notes/Sayfa \($0).md" }
        #expect(claims.relativeModifies(in: vault.root) == (linking + ["notes/Ham Zora.md"]).sorted())
        #expect(claims.moves == 1)
        #expect(result.updatedFiles == (linking + [Self.renamed]).sorted())
        #expect(result.failures == [RenameFailure(path: "notes/Ham Zora.md", reason: .rawField("raw"))])
        for (path, bytes) in before where path != Self.person {
            let expected = linking.contains(path) ? Data("Kurgu satır [[Zora Yeni]]\n".utf8) : bytes
            #expect(try vault.bytes(path) == expected, "\(path)")
        }
        try vault.check()
    }

    /// The portable fixture with a raw-field-only file: both reporting files are claimed, nothing else.
    @Test func theFrontmatterFixtureClaimsItsLinkSourceAndItsRawFieldFile() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try FileManager.default.removeItem(at: vault.root)
        try FileManager.default.copyItem(
            at: Fixtures.root().appendingPathComponent("rename/frontmatter/input"), to: vault.root)
        try vault.index.rebuild(vaultRoot: vault.root)
        let claims = ClaimLog()
        let store = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: claims)

        let result = try await store.renamingEntity(at: "places/Tepe Spor Salonu.md", to: "Liman Ofis")

        #expect(claims.relativeModifies(in: vault.root) == ["goals/Spor.md", "notes/Kitap.md"])
        #expect(result.failures.map(\.path) == ["goals/Spor.md", "notes/Kitap.md"])
    }

    private static func contents(of vault: StoreVault) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: vault.root.path) where path.hasSuffix(".md") {
            files[path] = try vault.bytes(path)
        }
        return files
    }
}

/// Records every claim and runs its accessor directly.
private final class ClaimLog: FileCoordination, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [FileCoordinationOperation] = []

    var moves: Int { lock.withLock { log.filter { if case .move = $0 { true } else { false } }.count } }

    func relativeModifies(in root: URL) -> [String] {
        let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return lock.withLock {
            log.compactMap {
                guard case .modify(let url) = $0 else { return nil }
                return String(url.path.dropFirst(prefix.count))
            }
        }
    }

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        lock.withLock { log.append(operation) }
        return try accessor(FileCoordinationAccess())
    }
}
