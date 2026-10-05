import Testing
import VaultFormat

struct RecurrenceTests {
    @Test func trailingUserTextIsRefused() throws {
        let input = try Fixtures.bytes(at: "write/task-recur-trailing-text/input.md")
        let document = RawDocument(bytes: input)
        let task = try #require(document.bodyLines.tasks.first)
        #expect(throws: EditError.contentNotRepresentable) {
            try document.settingTaskRecurrence(of: task, to: TaskRecurrence("every week"))
        }
        #expect(document.serialized() == input)
    }

    @Test func duplicateRulesFirstValidWinsAndUnknownRemovalIsRefused() throws {
        let source = "- [ ] Task 🔁 every weekday 🔁 every week 🔁 every day 📅 2026-10-04 ^id\n"
        let document = RawDocument(bytes: source.utf8)
        let task = try #require(document.bodyLines.tasks.first)
        #expect(task.recurrence?.rule == "every week")
        #expect(task.recurrenceSource == "every week")
        #expect(task.text == "Task 🔁 every weekday")
        #expect(throws: EditError.contentNotRepresentable) {
            try document.settingTaskRecurrence(of: task, to: nil)
        }
        #expect(document.serialized() == Array(source.utf8))
    }
    @Test func unsupportedRuleCompletesOrdinarilyAndRoundTrips() throws {
        let source = "- [ ] Task 🔁 every weekday 📅 2026-10-04 ^id\n"
        let document = RawDocument(bytes: source.utf8)
        #expect(document.serialized() == Array(source.utf8))
        let task = try #require(document.bodyLines.tasks.first)
        let completed = try document.changingStatus(of: task, to: .done, completionDate: CalendarDate("2026-10-04"))
        #expect(completed.bodyLines.tasks.count == 1)
        #expect(completed.bodyLines.tasks.first?.recurrenceSource == "every weekday")
        #expect(completed.bodyLines.tasks.first?.text == "Task 🔁 every weekday")
    }
    @Test func ruleConstructionRejectsInvalidInputsAndExtremeShifts() {
        #expect(TaskRecurrence(frequency: .interval(0, .day)) == nil)
        #expect(TaskRecurrence(frequency: .weekday(7)) == nil)
        #expect(TaskRecurrence("every -1 days") == nil)
        #expect(CalendarDate("0100-01-01")?.addingMonths(-1) == nil)
        #expect(CalendarDate("9999-12-31")?.addingMonths(1) == nil)
        #expect(CalendarDate("2026-10-04")?.addingMonths(Int.max) == nil)
    }
}
