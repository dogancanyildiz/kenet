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
        #expect(try await context.row("Deniz'i ara").due == CalendarDate("2026-10-05"))
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
        let linked = try await context.row("[[Mert Aksu (iş)|Mert Aksu]]")
        #expect(linked.text.spans.contains { $0.destination == entity.file })
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

    /// A weekday inside a recurrence (`her salı`) is not the task's date, so typing next to it must
    /// not look like the date changed.
    @Test(arguments: ["her salı", "her hafta", "every monday", "every week", "!! her cuma günü"])
    func pickedDateOutlivesEditsUntilTheTextNamesAnotherDate(expression: String) throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        model.mode = .task
        model.text = "\(expression) plan"
        let written = model.dueDate
        let picked = try #require(CalendarDate("2026-10-20"))
        model.selectDate(picked)
        for text in ["\(expression) plana", "\(expression) pla", "x \(expression) pla", "\(expression) pla "] {
            model.text = text
            #expect(model.overridesDate && model.dueDate == picked && !model.dateIsAssumed, "\(text)")
            #expect(model.recurrenceExpression != nil, "\(text)")
        }
        // Letter by letter, as the box reports it: only the finished word is a date.
        for length in 1..."yarın".count {
            model.text = "\(expression) pla " + "yarın".prefix(length)
            #expect(model.overridesDate == (length < "yarın".count), "\(model.text)")
        }
        #expect(model.dueDate == context.today.addingDays(1) && !model.dateIsAssumed)
        // The pick is gone for good, not hidden: taking the word back returns to what the text says.
        model.text = "\(expression) pla"
        #expect(!model.overridesDate && model.dueDate == written)
    }

    @Test func pickedDateFollowsTheWrittenDateOnlyWhenThatDateChanges() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        model.mode = .task
        model.text = "her salı plan 5 ekim"
        #expect(model.dueDate == CalendarDate("2026-10-05"))
        let picked = try #require(CalendarDate("2026-10-20"))
        model.selectDate(picked)
        model.text = "her salı planı 5 ekim"
        #expect(model.overridesDate && model.dueDate == picked)
        model.text = "her salı planı 6 ekim"
        #expect(!model.overridesDate && model.dueDate == CalendarDate("2026-10-06") && model.dateIsAssumed)
        // Removing the date by hand is a pick too.
        model.selectDate(nil)
        model.text = "her salı plan 6 ekim"
        #expect(model.overridesDate && model.dueDate == nil)
        model.text = "her salı plan"
        #expect(!model.overridesDate && model.dueDate == nil)
    }

    @Test func pickedDateIsWrittenWithTheWeekdayRecurrence() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "her salı pla"
        model.selectDate(CalendarDate("2026-10-20"))
        model.text = "her salı plan"
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "plan" && task.recurrence?.rule == "every tuesday")
        #expect(task.dueDate == CalendarDate("2026-10-20"))
    }

    @Test func undoneDateWordKeepsThePickedDateNextToAWeekdayRecurrence() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        model.mode = .task
        model.text = "her salı yarın ara"
        model.undoRecognition(try #require(model.taskExpressions.first { $0.spelling == "yarın" }))
        #expect(model.dueDate == nil)
        let picked = try #require(CalendarDate("2026-10-20"))
        model.selectDate(picked)
        model.text = "her salı yarın aras"
        #expect(model.overridesDate && model.dueDate == picked && model.submissionText == "yarın aras")
        // Changing the undone word forgets the undo; once it is a date again the pick drops.
        model.text = "her salı yarı aras"
        #expect(model.suppressedExpressions.isEmpty && model.overridesDate && model.dueDate == picked)
        model.text = "her salı yarın aras"
        #expect(!model.overridesDate && model.dueDate == context.today.addingDays(1))
    }
}
