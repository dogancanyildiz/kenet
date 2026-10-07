import Foundation
import Testing
import VaultFormat

@testable import Journal

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
    func row(_ text: String) throws -> TaskRow {
        try #require(store.content.tasks.first { $0.sourceText == text })
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
