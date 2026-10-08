import Foundation
import Testing
import VaultFormat

@testable import Journal

/// The task row menu's "Sil" only asks. The vault write belongs to the confirmed dialog.
@MainActor
struct TasksListRowDeleteTests {
    private static let taskText = "Hafta sonu dinlenme planı yap"

    /// Binds the row source to the flow below: the menu button requests a confirmation and
    /// the only delete call sits in the dialog's confirm closure.
    @Test func menuDeleteAsksAndOnlyTheDialogDeletes() throws {
        let source = try Self.rowSource()
        let menuButton = try #require(Self.block(after: "Button(\"Sil\"", in: source))
        #expect(menuButton.contains("deleteConfirmation.request(.pending)"))
        #expect(!menuButton.contains("delete()"), "the menu deletes without asking")

        let dialog = try #require(Self.block(after: ".destructiveConfirmationDialog(", in: source))
        #expect(dialog.contains("delete()"))
        #expect(source.components(separatedBy: "delete()").count == 2, "a second delete call bypasses the dialog")
    }

    @Test func pendingDeleteLeavesTheVaultUntilConfirmed() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let row = try #require(context.store.content.tasks.first { $0.sourceText == Self.taskText })
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

    private static func rowSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("App/Screens/Tasks/TasksListRow.swift"), encoding: .utf8)
    }

    /// The first `{ … }` block after `marker`, braces balanced.
    private static func block(after marker: String, in source: String) -> String? {
        guard let start = source.range(of: marker),
            let open = source[start.upperBound...].firstIndex(of: "{")
        else { return nil }
        var depth = 0
        for index in source[open...].indices {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            default: break
            }
        }
        return nil
    }
}
