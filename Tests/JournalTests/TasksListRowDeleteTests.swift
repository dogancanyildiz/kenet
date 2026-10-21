import Foundation
import Testing
import VaultFormat

@testable import Journal

/// The task row menu's "Sil" only asks. The vault write belongs to the confirmed dialog.
@MainActor
struct TasksListRowDeleteTests {
    private static let taskText = "Hafta sonu dinlenme planı yap"

    @Test func pendingDeleteLeavesTheVaultUntilConfirmed() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let row = try #require(try await context.store.allTasks().first { $0.sourceText == Self.taskText })
        let file = context.root.appendingPathComponent(row.file)
        let before = try Data(contentsOf: file)

        // What the menu button does.
        var confirmation = DestructiveConfirmation<DestructiveConfirmationToken>()
        confirmation.request(.pending)
        #expect(confirmation.isPending)
        #expect(try Data(contentsOf: file) == before)

        // Dismissing the dialog.
        confirmation.cancel()
        #expect(confirmation.confirm() == nil)
        #expect(try Data(contentsOf: file) == before)

        // Confirming it: only now the row's delete runs.
        confirmation.request(.pending)
        #expect(confirmation.confirm() == .pending)
        let editor = TaskEditorModel(store: context.store, row: row)
        await editor.load()
        #expect(await editor.delete())
        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(!after.contains(Self.taskText))
    }
}
