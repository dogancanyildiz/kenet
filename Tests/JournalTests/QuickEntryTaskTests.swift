import DateParsing
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct QuickEntryTaskTests {
    @Test func taskModeExtractsDateAndPreservesOtherSpacing() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        model.text = "5 ekim Deniz'i  ara"
        #expect(model.mode == .event && model.dueDate == nil)
        #expect(model.submissionText == model.text)
        model.mode = .task
        #expect(model.dueDate == CalendarDate("2026-10-05"))
        #expect(model.submissionText == "Deniz'i  ara")
        #expect(model.dateIsAssumed)
        #expect(model.entryTime == nil)
        model.selectDate(CalendarDate("2026-10-07"))
        #expect(model.dueDate == CalendarDate("2026-10-07") && !model.dateIsAssumed)
        model.selectDate(nil)
        #expect(model.dueDate == nil && model.submissionText == "Deniz'i  ara")
    }

    @Test func taskSubmissionWritesExactTasksBytesAndClearsDraft() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "5 ekim Deniz'i ara"
        #expect(await model.submit(time: try LineClock(hour: 13, minute: 0)))
        let document = try context.document()
        let task = try #require(document.bodyLines.tasks.first)
        let id = try #require(task.block.id)
        #expect(
            try Data(contentsOf: context.file)
                == Data(
                    "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Tasks\n- [ ] Deniz'i ara 📅 2026-10-05 ^\(id)\n"
                        .utf8))
        #expect(document.bodyLines.events.isEmpty)
        #expect(model.text.isEmpty && model.mode == .task && model.dueDate == nil)
        #expect(try context.row("Deniz'i ara").due == CalendarDate("2026-10-05"))
    }

    @Test func pinnedAmbiguousMentionSurvivesDateExtraction() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "5 ekim @Mert"
        let entity = try #require(model.suggestions().first { $0.qualifier == "iş" })
        model.selectSuggestion(entity)
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "[[Mert Aksu (iş)|Mert Aksu]]")
        #expect(task.dueDate == CalendarDate("2026-10-05"))
        #expect(try context.row("[[Mert Aksu (iş)|Mert Aksu]]").text.spans.contains { $0.destination == entity.file })
    }

    @Test func unresolvedTaskMentionKeepsDateAcrossResolution() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "5 ekim Mert Aksu ile görüş"
        #expect(await !model.submit(time: nil))
        #expect(model.text == "Mert Aksu ile görüş")
        #expect(model.dueDate == CalendarDate("2026-10-05") && model.dateIsAssumed)
        model.skip(try #require(model.pendingAmbiguity))
        #expect(await model.submit(time: nil))
        #expect(try context.document().bodyLines.tasks.first?.dueDate == CalendarDate("2026-10-05"))
    }

    @Test func removedDateAndUnknownCreationStillWriteOneTask() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "yarın @Ad ile görüş"
        model.selectDate(nil)
        #expect(await !model.submit(time: nil))
        await model.create(.person)
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "[[Ad]] ile görüş" && task.dueDate == nil)
        #expect(FileManager.default.fileExists(atPath: context.root.appendingPathComponent("people/Ad.md").path))
    }

    @Test func failedTaskWriteRetainsDateAndCannotSendDateOnly() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "yarın"
        #expect(!model.canSubmit)
        model.text = "yarın ara"
        let bytes = Data([0xFF, 0xFE])
        try bytes.write(to: context.file)
        #expect(await !model.submit(time: nil))
        #expect(model.text == "ara" && model.dueDate == CalendarDate("2026-10-04"))
        #expect(try Data(contentsOf: context.file) == bytes)
    }

    @Test func eventModeKeepsDateWordsAndHistoricalTaskWritesToday() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.text = "yarın ara"
        #expect(await model.submit(time: nil))
        let eventFile = context.root.appendingPathComponent("journal/\(LocalDay.today()).md")
        #expect(RawDocument(bytes: try Data(contentsOf: eventFile)).bodyLines.events.first?.block.text == "yarın ara")
        let date = context.today
        let historical = QuickEntryModel(store: context.store, day: CalendarDate("2026-09-12"), today: { date })
        historical.languages = [.turkish, .english]
        historical.mode = .task
        historical.text = "yarın ara"
        #expect(await historical.submit(time: nil))
        #expect(try context.document().bodyLines.tasks.count == 1)
    }
}
