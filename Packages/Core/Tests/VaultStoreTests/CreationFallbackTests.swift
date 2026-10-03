import Foundation
import Testing
import VaultFormat

@testable import VaultStore

struct CreationFallbackTests {
    @Test func unsupportedHardLinksStillCreateEntitiesAndDays() async throws {
        let vault = try StoreVault(linkFile: { _, _ in throw CocoaError(.fileWriteUnknown) })
        defer { vault.remove() }
        let path = try await vault.store.creatingEntity(kind: .person, name: "Deniz Arıkan")
        #expect(try vault.bytes(path) == Data("---\ntype: person\nname: Deniz Arıkan\n---\n".utf8))
        try await vault.store.addingEvent(on: storeDate, text: "[[Deniz Arıkan]]")
        #expect(
            try vault.bytes()
                == Data("---\ntype: journal\ndate: 2026-09-27\n---\n\n## Events\n- [[Deniz Arıkan]] ^aaaaaa\n".utf8))
        #expect(try vault.index.links(to: path).count == 1)
        try vault.check()
        try expectNoTemporaryFiles(vault.root)
    }

    @Test func fallbackCannotOverwriteExistingFile() throws {
        let vault = try StoreVault(linkFile: { _, _ in throw CocoaError(.fileWriteUnknown) })
        defer { vault.remove() }
        try vault.write("people/Deniz Arıkan.md", "Kitap")
        let url = vault.root.appendingPathComponent("people/Deniz Arıkan.md")
        #expect(throws: VaultStoreError.nameTaken) {
            try vault.store.atomicWrite(Data("Su".utf8), to: url, exclusive: true)
        }
        #expect(try vault.bytes("people/Deniz Arıkan.md") == Data("Kitap".utf8))
        try expectNoTemporaryFiles(vault.root)
    }

    @Test(arguments: ["cocoa", "posix", "underlying-posix"])
    func existingFileErrorsNeverEnterFallback(kind: String) throws {
        let vault = try StoreVault(linkFile: { _, _ in
            switch kind {
            case "cocoa": throw CocoaError(.fileWriteFileExists)
            case "posix": throw POSIXError(.EEXIST)
            default:
                throw NSError(
                    domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                    userInfo: [NSUnderlyingErrorKey: POSIXError(.EEXIST)])
            }
        })
        defer { vault.remove() }
        let url = vault.root.appendingPathComponent("people/Deniz Arıkan.md")
        #expect(throws: VaultStoreError.nameTaken) {
            try vault.store.atomicWrite(Data("Su".utf8), to: url, exclusive: true)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try expectNoTemporaryFiles(vault.root)
    }

    @Test(arguments: ["event", "task", "journal"])
    func dayCreationRaceRereadsAndRetainsExternalContent(operation: String) async throws {
        let calls = LinkAttempts()
        let vault = try StoreVault(linkFile: { source, destination in
            _ = calls.tick()
            try Data("## Events\n- Selin ^keepme\n".utf8).write(to: destination, options: .withoutOverwriting)
            try FileManager.default.linkItem(at: source, to: destination)
        })
        defer { vault.remove() }
        let result = try await changeDay(vault.store, operation: operation)
        #expect(calls.count == 1)
        #expect(result.frontmatter == .absent)
        #expect(result.bodyLines.events.contains { $0.block.text == "Selin" && $0.block.id == "keepme" })
        switch operation {
        case "event": #expect(result.bodyLines.events.map { $0.block.text } == ["Selin", "Kitap"])
        case "task": #expect(result.bodyLines.tasks.map { $0.block.text } == ["Kitap"])
        default: #expect(try vault.bytes() == Data("## Events\n- Selin ^keepme\n\n## Journal\nKitap\n".utf8))
        }
        try vault.check()
        try expectNoTemporaryFiles(vault.root)
    }

    @Test(arguments: ["event", "task", "journal"])
    func secondDayCreationCollisionIsStaleTarget(operation: String) async throws {
        let calls = LinkAttempts()
        let vault = try StoreVault(linkFile: { _, _ in
            _ = calls.tick()
            throw POSIXError(.EEXIST)
        })
        defer { vault.remove() }
        await #expect(throws: VaultStoreError.staleTarget) { try await changeDay(vault.store, operation: operation) }
        #expect(calls.count == 2)
        #expect(try vault.index.files().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(storePath).path))
        try expectNoTemporaryFiles(vault.root)
    }

    private func changeDay(_ store: VaultStore, operation: String) async throws -> RawDocument {
        switch operation {
        case "event": try await store.addingEvent(on: storeDate, text: "Kitap")
        case "task": try await store.addingTask(on: storeDate, text: "Kitap")
        default: try await store.changingJournal(on: storeDate, to: "Kitap")
        }
    }

    private func expectNoTemporaryFiles(_ root: URL) throws {
        #expect(
            try FileManager.default.subpathsOfDirectory(atPath: root.path).allSatisfy {
                !URL(fileURLWithPath: $0).lastPathComponent.hasPrefix(".vault-store-")
            })
    }
}

private final class LinkAttempts: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func tick() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
