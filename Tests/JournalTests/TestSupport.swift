import Foundation
import Testing

@testable import Journal

final class TestDefaults {
    let name = "JournalTests-" + UUID().uuidString
    let defaults: UserDefaults

    init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
    func clean() { defaults.removePersistentDomain(forName: name) }
}

func testDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func pathBookmarks(stale: Bool = false) -> VaultBookmarks {
    VaultBookmarks(
        resolve: { data in
            let path = try #require(String(data: data, encoding: .utf8))
            return (URL(fileURLWithPath: path), stale)
        },
        create: { Data($0.path.utf8) }, isMalformed: { String(data: $0, encoding: .utf8) == nil })
}

actor UpdateGate {
    private var armed = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    var blocked: Bool { continuation != nil }
    func arm() { armed = true }
    func hold() async {
        calls += 1
        guard armed else { return }
        armed = false
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

func waitForGate(_ gate: UpdateGate) async throws {
    for _ in 0..<150 {
        if await gate.blocked { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Expected index operation to suspend")
}
