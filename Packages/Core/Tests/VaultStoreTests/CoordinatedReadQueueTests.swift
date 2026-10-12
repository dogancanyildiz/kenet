import Foundation
import Testing
import VaultFormat

@testable import VaultStore

/// A coordinated read can wait a long time (an iCloud download). It must hold only its own read,
/// never the store: writes and other reads of the vault go on while it waits.
struct CoordinatedReadQueueTests {
    private static let held = "people/Deniz Arıkan.md"

    /// The write must finish while the read is still held. If the read held the actor, the write
    /// could only start after the coordinator's fallback released the read, and the check fails.
    @Test(.timeLimit(.minutes(1)))
    func aWriteFinishesWhileAReadIsHeld() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let coordination = HeldReadCoordination(holding: Self.held)
        let store = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: coordination)
        let read = Task { try await store.document(at: Self.held) }
        await coordination.readStarted()

        let written = try await store.addingEvent(on: storeDate, text: "Kurgu yazma")
        let heldWhileWriting = coordination.isHolding
        coordination.release()

        #expect(heldWhileWriting)
        #expect(written.bodyLines.events.map(\.block.text).contains("Kurgu yazma"))
        #expect(try await read.value == RawDocument(bytes: Array(try vault.bytes(Self.held))))
        #expect(try vault.bytes() == Data(written.serialized()))
        try vault.check()
    }

    /// Reads need no order among themselves: one held read does not queue the next one behind it.
    @Test(.timeLimit(.minutes(1)))
    func anotherReadFinishesWhileAReadIsHeld() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let coordination = HeldReadCoordination(holding: Self.held)
        let store = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: coordination)
        let read = Task { try await store.document(at: Self.held) }
        await coordination.readStarted()

        let day = try await store.dayDocument(for: storeDate)
        let heldWhileReading = coordination.isHolding
        coordination.release()

        #expect(heldWhileReading)
        #expect(day == RawDocument(bytes: Array(try vault.bytes())))
        #expect(try await read.value == RawDocument(bytes: Array(try vault.bytes(Self.held))))
        #expect(coordination.operations.filter { if case .read = $0 { true } else { false } }.count == 2)
    }

    #if canImport(Darwin)
        /// Writes replace the file whole: reads racing a run of writes each see one written version,
        /// never a torn or empty file. The reads keep going until every write has finished.
        @Test(.timeLimit(.minutes(1)))
        func readsRacingWritesSeeWholeVersions() async throws {
            let vault = try StoreVault(sample: true, random: { UInt64.random(in: .min ... .max) })
            defer { vault.remove() }
            let store = vault.store
            let initial = try vault.bytes()
            let finished = WritesFinished()
            let writes = Task {
                defer { finished.mark() }
                var versions: [Data] = []
                for number in 0..<100 {
                    versions.append(
                        Data(try await store.addingEvent(on: storeDate, text: "Yarış \(number)").serialized()))
                }
                return versions
            }
            var reads: [Data] = []
            while reads.count < 1000 || !finished.value {
                reads.append(Data(try await store.dayDocument(for: storeDate).serialized()))
            }
            let versions = Set([initial] + (try await writes.value))
            print("readsRacingWritesSeeWholeVersions: \(reads.count) reads, \(Set(reads).count) versions seen")

            #expect(versions.count == 101)
            #expect(reads.allSatisfy { versions.contains($0) })
            try vault.check()
        }
    #endif

    /// A rejected read still reports the coordinator's error, and nothing is read.
    @Test func aDeniedReadThrowsTheCoordinatorsError() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let store = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: DenyingCoordination())
        await #expect(throws: DenyingCoordination.Denied()) { try await store.document(at: storePath) }
        await #expect(throws: VaultStoreError.invalidPath) { try await store.document(at: "../dışarı.md") }
    }
}

/// Holds the coordinated read of one vault path until released. A fallback releases it after 45
/// seconds (inside the tests' one-minute limit) so a store that waits for the read cannot hang the
/// run; the tests then fail instead. A working store never reaches it, however slow the machine.
private final class HeldReadCoordination: FileCoordination, @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var started = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var log: [FileCoordinationOperation] = []

    init(holding path: String) { self.path = path }

    var operations: [FileCoordinationOperation] { lock.withLock { log } }
    var isHolding: Bool { lock.withLock { started && !released } }

    func readStarted() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock {
                if started { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        lock.withLock { released = true }
        gate.signal()
    }

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        lock.withLock { log.append(operation) }
        if case .read(let url) = operation, url.path.hasSuffix("/" + path) {
            let ready = lock.withLock {
                started = true
                defer { waiters = [] }
                return waiters
            }
            for waiter in ready { waiter.resume() }
            if gate.wait(timeout: .now() + 45) == .timedOut { lock.withLock { released = true } }
        }
        return try accessor(FileCoordinationAccess())
    }
}

private final class WritesFinished: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    var value: Bool { lock.withLock { finished } }
    func mark() { lock.withLock { finished = true } }
}

private struct DenyingCoordination: FileCoordination {
    struct Denied: Error, Equatable {}

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        throw Denied()
    }
}
