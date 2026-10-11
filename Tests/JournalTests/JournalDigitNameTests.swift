import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Journal writing hands every changed line to the recognizer; a digit-only name is linked only after `@`.
@MainActor
struct JournalDigitNameTests {
    private func context() async throws -> DayEditingTestContext {
        let context = try DayEditingTestContext()
        // `2026-10-12` is not digit-only: only the task's structure keeps it out of the due date.
        for name in ["12", "2026", "10", "30", "5", "1", "2026-10-12"] {
            try Data("---\ntype: place\nname: \(name)\n---\n".utf8)
                .write(to: context.root.appendingPathComponent("places/\(name).md"))
        }
        await context.start()
        return context
    }

    private func body(_ context: DayEditingTestContext) throws -> String {
        try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
    }

    @Test func plainNumbersStayAsWrittenAndOnlyAnExplicitDigitNameIsLinked() async throws {
        let context = try await context()
        defer { context.clean() }
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        let plain =
            "saat 12:30'da buluştuk, 12.10.2026 günü 12,5 km yürüdük.\n12 Ekim 2026: bugün 12 kişi geldi.\n1. Elma\n"
        model.text = plain + "@12 de geldi.\n" + model.text
        #expect(await model.save())
        #expect(try body(context).hasPrefix(plain + "[[12]] de geldi.\n"))
    }

    @Test func journalTaskKeepsItsDueDateThroughEveryEdit() async throws {
        let context = try await context()
        defer { context.clean() }
        let due = CalendarDate("2026-10-12")
        func journalTask() throws -> TaskLine? {
            RawDocument(bytes: try Data(contentsOf: context.file)).bodyLines.tasks.first { $0.text.contains("ara") }
        }
        var model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = "- [ ] ara 📅 2026-10-12\n" + model.text
        #expect(await model.save())
        #expect(try body(context).hasPrefix("- [ ] ara 📅 2026-10-12\n"))
        #expect(try journalTask()?.dueDate == due)
        // Every later edit of the same line is recognized again as a changed line.
        for (old, new, expected) in [
            ("- [ ] ara", "- [ ] Deniz'i ara", "- [ ] [[Deniz Arıkan|Deniz]]'i ara 📅 2026-10-12\n"),
            ("'i ara 📅", "'i 12 kez @12 ara 📅", "- [ ] [[Deniz Arıkan|Deniz]]'i 12 kez [[12]] ara 📅 2026-10-12\n"),
            (
                "2026-10-12\n", "2026-10-12 ⏳ 2026-10-11 ⏫\n",
                "- [ ] [[Deniz Arıkan|Deniz]]'i 12 kez [[12]] ara 📅 2026-10-12 ⏳ 2026-10-11 ⏫\n"
            ),
        ] {
            model = JournalEditorModel(store: context.store, day: context.day)
            await model.load()
            let range = try #require(model.text.range(of: old))
            model.text = model.text.replacingCharacters(in: range, with: new)
            #expect(await model.save())
            #expect(try body(context).hasPrefix(expected))
            #expect(try journalTask()?.dueDate == due)
        }
    }
}
