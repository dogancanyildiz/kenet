import Foundation
import Testing
import VaultFormat

@testable import Kenet

@MainActor
struct TaskTestContext {
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore
    let today = CalendarDate("2026-10-03")!

    init(sample: Bool = false) throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent("Vault")
        defaults = try TestDefaults()
        if sample {
            let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/sample")
            try FileManager.default.copyItem(at: fixtures, to: root)
        }
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
    }

    func start() async { await store.start() }
    var file: URL { root.appendingPathComponent("journal/\(today).md") }
    func document() throws -> RawDocument { RawDocument(bytes: try Data(contentsOf: file)) }
    /// The task written as `text` once the index has it. A test's outside write ends in a
    /// refresh that can meet one the watcher already started; the row arrives with that one, so
    /// the query is asked again for up to 5 s before the test fails.
    func row(_ text: String) async throws -> TaskRow {
        for _ in 0..<50 {
            if let row = try await store.allTasks().first(where: { $0.sourceText == text }) { return row }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try #require(try await store.allTasks().first { $0.sourceText == text })
    }
    func model() -> QuickEntryModel {
        let date = today
        let model = QuickEntryModel(store: store, today: { date })
        model.languages = [.turkish, .english]
        return model
    }
    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
