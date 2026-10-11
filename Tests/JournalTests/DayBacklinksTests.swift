import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

@MainActor struct DayBacklinksTests {
    private static func writeDay(_ date: String, in root: URL) throws {
        let text = "---\ntype: journal\ndate: \(date)\n---\n\n## Tasks\n\n## Events\n\n## Journal\n"
        let file = root.appendingPathComponent("journal/\(date).md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private static func writeNote(_ name: String, content: String, in root: URL) throws {
        let file = root.appendingPathComponent("notes/\(name).md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test func backlinksLoadOnlyWhenPresent() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let targetDay = try #require(CalendarDate("2026-10-02"))
        try Self.writeDay("2026-10-02", in: context.root)
        try Self.writeNote("Proje Fikirleri", content: "Toplantı [[2026-10-02]] günü yapılacak.\n", in: context.root)
        await context.start()

        let model = DayBacklinksModel(store: context.store)
        #expect(model.items.isEmpty && !model.hasLoaded)

        await model.load(day: targetDay)
        #expect(model.hasLoaded)
        #expect(model.items.count == 1)
        #expect(model.items[0].sourceTitle == "Proje Fikirleri")
        #expect(model.items[0].sourceKind == "note")
        #expect(model.items[0].text.contains("[[2026-10-02]]"))

        // Another day with no backlinks produces an empty list
        let emptyDay = try #require(CalendarDate("2026-10-03"))
        try Self.writeDay("2026-10-03", in: context.root)
        await model.load(day: emptyDay)
        #expect(model.hasLoaded)
        #expect(model.items.isEmpty)
    }

    @Test func anotherVaultNeverKeepsPreviousBacklinks() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let targetDay = try #require(CalendarDate("2026-10-02"))
        try Self.writeDay("2026-10-02", in: context.root)
        try Self.writeNote("Proje Fikirleri", content: "Toplantı [[2026-10-02]] günü yapılacak.\n", in: context.root)
        await context.start()

        let model = DayBacklinksModel(store: context.store)
        await model.load(day: targetDay)
        #expect(model.items.count == 1)

        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        #expect(context.store.vaultURL?.lastPathComponent == "Other")

        await model.load(day: targetDay)
        #expect(model.items.isEmpty && model.hasLoaded)
    }
}
