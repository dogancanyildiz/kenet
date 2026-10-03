import Foundation
import Testing
import VaultIndex

@testable import VaultStore

struct PersistenceRegressionTests {
    @Test func atomicReplacementPreservesPrivatePermissions() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Events\n- Kitap ^keepme\n")
        let url = vault.root.appendingPathComponent(storePath)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try await vault.store.addingEvent(on: storeDate, text: "Su")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        try vault.check()
    }

    #if os(macOS)
        @Test func atomicReplacementPreservesExtendedAttributes() async throws {
            let vault = try StoreVault()
            defer { vault.remove() }
            try vault.write(storePath, "## Events\n- Kitap ^keepme\n")
            let url = vault.root.appendingPathComponent(storePath)
            try await xattr(["-w", "com.dravcore.journal.test", "Su", url.path])
            try await vault.store.addingEvent(on: storeDate, text: "Deniz")
            #expect(try await xattr(["-p", "com.dravcore.journal.test", url.path]) == "Su\n")
            try vault.check()
        }

        @discardableResult
        private func xattr(_ arguments: [String]) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                // Waiting synchronously here can starve the cooperative executor during parallel tests.
                process.terminationHandler = { process in
                    let output = pipe.fileHandleForReading.readDataToEndOfFile()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: String(decoding: output, as: UTF8.self))
                    } else {
                        continuation.resume(
                            throwing: NSError(
                                domain: "VaultStoreTests.xattr", code: Int(process.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: String(decoding: output, as: UTF8.self)]))
                    }
                }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        }
    #endif

    @Test func exclusivePublishingCannotReplaceAnExistingFile() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let url = vault.root.appendingPathComponent("people/Deniz Arıkan.md")
        try vault.write("people/Deniz Arıkan.md", "Kitap")
        #expect(throws: VaultStoreError.nameTaken) {
            try vault.store.atomicWrite(Data("Su".utf8), to: url, exclusive: true)
        }
        #expect(try Data(contentsOf: url) == Data("Kitap".utf8))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == [
                url.lastPathComponent
            ])
    }

    @Test func twoIndependentPublishersHaveExactlyOneWinner() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let second = VaultStore(vaultRoot: vault.root, index: vault.index)
        let url = vault.root.appendingPathComponent("people/Deniz Arıkan.md")
        let winners = try await withThrowingTaskGroup(of: Int.self) { group in
            for number in 0..<2 {
                group.addTask {
                    let store = number == 0 ? vault.store : second
                    do {
                        try store.atomicWrite(Data((number == 0 ? "Kitap" : "Su").utf8), to: url, exclusive: true)
                        return 1
                    } catch VaultStoreError.nameTaken {
                        return 0
                    }
                }
            }
            var count = 0
            for try await result in group { count += result }
            return count
        }
        #expect(winners == 1)
        #expect([Data("Kitap".utf8), Data("Su".utf8)].contains(try Data(contentsOf: url)))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == [
                url.lastPathComponent
            ])
    }
}
