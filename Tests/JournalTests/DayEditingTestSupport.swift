import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct DayEditingTestContext {
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore
    let day = CalendarDate("2026-09-12")!
    var file: URL { root.appendingPathComponent("journal/\(day).md") }

    init() throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent("sample")
        defaults = try TestDefaults()
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("vaults/sample"), to: root)
        try Data(contentsOf: fixtures.appendingPathComponent("journal/edit/input.md"))
            .write(to: root.appendingPathComponent("journal/2026-09-12.md"))
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
    }

    func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/journal/edit/" + name)
    }
    func start() async { await store.select(root) }
    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
