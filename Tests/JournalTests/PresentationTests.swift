import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

/// Screen data is checked against the same fictional vault used by Core.
struct PresentationTests {
    @Test func sampleDayRowsAndEventOrder() throws {
        let content = try sampleContent()
        #expect(content.days.count == 14)
        #expect(content.days.flatMap(\.events).count == 40)
        #expect(content.days.first?.date.description == "2026-09-27")
        #expect(content.days.last?.date.description == "2026-09-14")
        let day = content.day(on: try #require(CalendarDate("2026-09-20")))
        #expect(day.id == "journal/2026-09-20.md")
        #expect(day.events.count == 2)
        #expect(day.events.map { $0.time?.raw } == ["11:00", "16:00"])
        #expect(
            day.events.map(\.text.plainText) == ["Ev'de dinlenme ve haftalık plan", "Ece Yalın ile sergi ziyareti"])
        #expect(day.preview == "Pazar gününü evde toparlanarak geçirdim. Öğleden sonra Ece ile sergiyi gezdik.")
        let link = try #require(day.journal.first?.text.spans.first { $0.text == "Ece" })
        #expect(link.destination == "people/Ece Yalın.md")
    }

    @Test func entitiesAreSortedWithQualifiersAndAliases() throws {
        let content = try sampleContent()
        let people = content.entities.filter { $0.kind == "person" }
        #expect(
            people.map(\.name) == [
                "Baran Tunç", "Deniz Arıkan", "Ece Yalın", "Mert Aksu", "Mert Aksu", "Selin Korkmaz",
            ])
        let mert = people.filter { $0.name == "Mert Aksu" }
        #expect(mert.map(\.qualifier) == [nil, "iş"])
        #expect(mert[1].aliases == ["Mert"])
        let ece = try #require(people.first { $0.name == "Ece Yalın" })
        #expect(ece.aliases == ["Ece"])
        #expect(ece.incomingLinks == 5)
        #expect(content.entities.filter { $0.kind == "place" }.count == 4)
        #expect(!content.entities.contains { $0.kind == "goal" })
    }

    @Test func emptyDaysAndNestedJournalHeadings() throws {
        let content = try sampleContent()
        let empty = content.day(on: try #require(CalendarDate("2026-10-03")))
        #expect(empty.id == "journal/2026-10-03.md")
        #expect(empty.events.isEmpty && empty.journal.isEmpty && empty.preview == nil)
        let day = content.day(on: try #require(CalendarDate("2026-09-22")))
        #expect(day.events.isEmpty)
        #expect(day.journal.contains { $0.headingLevel == 3 && $0.text.plainText == "Akşam" })
        #expect(day.journal.last?.headingLevel == nil)
    }

    @Test func localDayChangesAtLocalMidnightAndTimesStayLocal() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-20T22:30:00Z"))
        let east = try #require(TimeZone(secondsFromGMT: 3 * 3600))
        let west = try #require(TimeZone(secondsFromGMT: -7 * 3600))
        #expect(LocalDay.today(at: instant, timeZone: east).description == "2026-09-21")
        #expect(LocalDay.today(at: instant, timeZone: west).description == "2026-09-20")
        let time = try #require(try sampleContent().days.flatMap(\.events).first?.time)
        let day = try #require(CalendarDate("2026-09-20"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = east
        let components = calendar.dateComponents(
            [.day, .hour, .minute], from: LocalDay.instant(for: day, time: time, timeZone: east))
        #expect(components.day == 20 && components.hour == time.hour && components.minute == time.minute)
    }

    @Test func sourceOrderAndLiteralCodeArePreserved() throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appendingPathComponent("vault")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("journal"), withIntermediateDirectories: true)
        let text =
            "## Events\n- 16:00 [[Ece Yalın|Ece]] ve `[[Ev]]`\n- Saat yok\n- 9:00 Önceki saat\n\n## Journal\nBirinci satır\nikinci satır [[Ev|evde]].\n"
        try Data(text.utf8).write(to: root.appendingPathComponent("journal/2026-09-20.md"))
        let index = try VaultIndex(databaseURL: temp.appendingPathComponent("index.sqlite"))
        _ = try index.refresh(vaultRoot: root)
        let day = VaultReadModel(snapshot: try index.snapshot()).days[0]
        #expect(day.events.map { $0.time?.raw } == ["16:00", nil, "9:00"])
        #expect(day.events[0].text.plainText == "Ece ve `[[Ev]]`")
        #expect(day.journal[0].text.plainText == "Birinci satır\nikinci satır evde.")
        #expect(day.preview == "Birinci satır")
    }

    private func sampleContent() throws -> VaultReadModel {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/sample")
        let root = temp.appendingPathComponent("vault")
        try FileManager.default.copyItem(at: source, to: root)
        let index = try VaultIndex(databaseURL: temp.appendingPathComponent("index.sqlite"))
        _ = try index.refresh(vaultRoot: root)
        return VaultReadModel(snapshot: try index.snapshot())
    }
}

@MainActor
struct PresentationUpdateTests {
    @Test func watcherPublishesDayContentTogetherWithCounts() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks()),
            supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        let root = try #require(store.vaultURL)
        let file = root.appendingPathComponent("journal/2026-09-20.md")
        try Data("## Events\n- 11:00 Bir an\n".utf8).write(to: file)
        for _ in 0..<150 {
            if store.content.days.first?.events.count == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.content.days.first?.events.first?.text.plainText == "Bir an")
        #expect(store.counts.events == 1)
        try Data("## Events\n- 11:00 Yeni metin\n".utf8).write(to: file, options: .atomic)
        for _ in 0..<150 {
            if store.content.days.first?.events.first?.text.plainText == "Yeni metin" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.content.days.first?.events.first?.text.plainText == "Yeni metin")
        try Data("---\ntype: person\nname: Ece Yalın\naliases: [Ece]\n---\n".utf8)
            .write(to: root.appendingPathComponent("people/Ece Yalın.md"))
        for _ in 0..<150 {
            if store.content.entities.count == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.content.entities.first?.name == "Ece Yalın")
        #expect(store.content.entities.first?.aliases == ["Ece"])
        #expect(store.counts.entities == 1)
        let other = temp.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await store.select(other)
        for _ in 0..<150 {
            if store.vaultURL == other && !store.isProcessing { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.vaultURL == other)
        #expect(store.content.days.isEmpty && store.content.entities.isEmpty)
    }
}
