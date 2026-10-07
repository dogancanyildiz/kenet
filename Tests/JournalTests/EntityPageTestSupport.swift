import Foundation
import Testing

@testable import Journal

@MainActor
struct EntityPageTestContext {
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore
    let path = "people/Deniz Arıkan.md"
    var file: URL { root.appendingPathComponent(path) }

    init(extendedFields: Bool = false) throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent("sample")
        defaults = try TestDefaults()
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("vaults/sample"), to: root)
        if extendedFields {
            try Data(contentsOf: fixtures.appendingPathComponent("entities/fields/input.md")).write(
                to: root.appendingPathComponent("people/Deniz Arıkan.md"))
        }
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
    }
    func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/entities/fields/" + name)
    }
    func start() async { await store.select(root) }
    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
