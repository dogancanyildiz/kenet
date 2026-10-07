import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

struct TasksListRowCompletionTests {
    @Test func closedRowFactoryAllowsReopen() throws {
        let row = try taskRow(status: "x")
        let action = TasksListRowCompletion.make(
            from: row, allowsReopening: true, isBusy: false, canAddEvent: true)
        #expect(action.canToggleCompletion)
        // Catalog key (not localized display); callers pass it as LocalizedStringKey.
        #expect(action.boxAccessibilityLabelKey == "Görevi yeniden aç")
    }

    @Test func openRowUsesCompleteLabel() throws {
        let row = try taskRow(status: " ")
        let action = TasksListRowCompletion.make(
            from: row, allowsReopening: true, isBusy: false, canAddEvent: true)
        #expect(action.canToggleCompletion)
        #expect(action.boxAccessibilityLabelKey == "Görevi tamamla")
    }

    @Test func closedWithoutReopeningCannotToggle() throws {
        let row = try taskRow(status: "x")
        let action = TasksListRowCompletion.make(
            from: row, allowsReopening: false, isBusy: false, canAddEvent: true)
        #expect(!action.canToggleCompletion)
        #expect(action.boxAccessibilityLabelKey == "Görevi tamamla")
    }

    @Test func busyOrReadOnlyBlocksToggle() throws {
        let row = try taskRow(status: " ")
        #expect(
            !TasksListRowCompletion.make(
                from: row, allowsReopening: true, isBusy: true, canAddEvent: true
            ).canToggleCompletion)
        #expect(
            !TasksListRowCompletion.make(
                from: row, allowsReopening: true, isBusy: false, canAddEvent: false
            ).canToggleCompletion)
    }

    private func taskRow(status: String) throws -> TaskRow {
        var fields: [String: Any] = [
            "file": "journal/2026-09-20.md", "ordinal": 1, "kind": "task", "firstLine": 2,
            "lastLine": 2, "text": "Sample task", "section": "Tasks", "rawStatus": status,
            "ownsIdentifier": false,
        ]
        if status == "x" || status == "X" {
            fields["doneDate"] = "2026-09-20"
        }
        let block = try JSONDecoder().decode(
            IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        return TaskRow(row: block, links: [])
    }
}
