import Testing
import VaultFormat

struct TaskFieldTests {
    @Test func invalidDatesRemainTextAndHaveNoFieldRanges() {
        let document = RawDocument(bytes: "- [ ] x 📅 2026-13-40 🛫 2026-02-29".utf8)
        let task = document.bodyLines.tasks[0]
        #expect(task.dueDate == nil && task.startDate == nil)
        #expect(task.fieldRanges.isEmpty)
        #expect(task.text == "x 📅 2026-13-40 🛫 2026-02-29")
    }

    @Test func fieldsAreNotTextAndFirstProjectWins() {
        let task = RawDocument(bytes: "- [ ] x 📅 2026-10-05 y #project/ilk #project/son 🔺".utf8).bodyLines.tasks[0]
        #expect(task.text == "x y")
        #expect(task.project == "ilk")
        #expect(task.priority == .other("🔺"))
        #expect(task.fieldRanges.count == 4)
    }

    @Test func completionWritesDateAndReopeningRemovesIt() throws {
        let document = RawDocument(bytes: "- [ ] x ^id".utf8)
        let completed = try document.changingStatus(
            of: document.bodyLines.tasks[0], to: .done,
            completionDate: CalendarDate("2026-10-03"))
        #expect(completed.bodyLines.tasks[0].doneDate == CalendarDate("2026-10-03"))
        #expect(String(decoding: completed.serialized(), as: UTF8.self) == "- [x] x ✅ 2026-10-03 ^id")
        let reopened = try completed.changingStatus(of: completed.bodyLines.tasks[0], to: .todo)
        #expect(reopened.bodyLines.tasks[0].doneDate == nil)
        #expect(reopened.serialized() == document.serialized())
    }

    @Test func fieldEditsAreIdempotentAndRejectUnexpectedMetadataInText() throws {
        let document = RawDocument(bytes: "- [ ] x 📅 2026-10-05 y ^id".utf8)
        let changed = try document.settingTaskDueDate(of: document.bodyLines.tasks[0], to: CalendarDate("2026-10-07"))
        let twice = try changed.settingTaskDueDate(of: changed.bodyLines.tasks[0], to: CalendarDate("2026-10-07"))
        #expect(twice.serialized() == changed.serialized())
        #expect(throws: EditError.contentNotRepresentable) {
            try document.changingText(of: document.bodyLines.tasks[0].block, to: "x #project/accidental")
        }
    }

    @Test func referenceLinksProtectFieldsFromRemoval() throws {
        let source = "- [ ] [x 📅 2026-10-05 y][r] [🛫 2026-10-01 🔼 #project/x][] ^id\n\n[r]: https://example.com\n"
        let document = RawDocument(bytes: source.utf8)
        let task = document.bodyLines.tasks[0]
        #expect(task.dueDate == nil && task.startDate == nil && task.priority == nil && task.project == nil)
        #expect(task.fieldRanges.isEmpty)
        let edited = try document.settingTaskDueDate(of: task, to: nil)
        #expect(edited.serialized() == document.serialized())
    }

    @Test func typedAdditionPreservesRawTextSpacing() throws {
        let text = "a  b `a  b` [a  b](https://example.com) [a  b][r]"
        let document = try RawDocument(bytes: "## Tasks\n".utf8).addingTask(
            text: text, id: "id", due: CalendarDate("2026-10-05"))
        #expect(
            String(decoding: document.serialized(), as: UTF8.self)
                == "## Tasks\n- [ ] " + text + " 📅 2026-10-05 ^id\n")
        #expect(document.bodyLines.tasks[0].text == "a b `a b` [a b](https://example.com) [a b][r]")
    }

    @Test func cancelledCompletionRequiresNewDateAndReplacesOldDate() throws {
        let document = RawDocument(bytes: "- [-] x ✅ 2026-10-02 ^id".utf8)
        let task = document.bodyLines.tasks[0]
        #expect(throws: EditError.invalidValue) {
            try document.changingStatus(of: task, to: .done)
        }
        let completed = try document.changingStatus(
            of: task, to: .done, completionDate: CalendarDate("2026-10-04"))
        #expect(String(decoding: completed.serialized(), as: UTF8.self) == "- [x] x ✅ 2026-10-04 ^id")
        #expect(
            try completed.changingStatus(of: completed.bodyLines.tasks[0], to: .done).serialized()
                == completed.serialized())
    }

}
