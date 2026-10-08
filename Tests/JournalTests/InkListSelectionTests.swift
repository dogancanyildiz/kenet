import Foundation
import Testing

@testable import Journal

/// Mac list-column selection: one fill token, body contrast on that fill (`docs/design.md` rule 4).
struct InkListSelectionTests {
    private static let bodyMinimum = 4.5

    @Test func fillAndMarkArePaletteTokens() {
        #expect(InkListSelectionChrome.fill == .well)
        #expect(InkListSelectionChrome.mark == .accent)
        #expect(InkListSelectionChrome.markWidth == InkSize.modeUnderline)
    }

    @Test func rowTextMeetsBodyContrastOnSelectionFill() {
        for token in InkListSelectionChrome.textTokens {
            for appearance in InkPalette.Appearance.allCases {
                let ratio = InkPalette.contrastRatio(
                    foreground: token.variant.hex(for: appearance),
                    background: InkListSelectionChrome.fill.variant.hex(for: appearance))
                #expect(
                    ratio + 0.000_1 >= Self.bodyMinimum,
                    "\(token.rawValue) on selection \(appearance.rawValue): \(ratio)")
            }
        }
    }

    @Test func taskRowClickKeepsBoxLinkAndRowApart() {
        #expect(TasksListRowInteraction.action(for: .box, hasLink: true, isMac: true) == .toggleCompletion)
        #expect(TasksListRowInteraction.action(for: .link, hasLink: true, isMac: true) == .openLink)
        #expect(TasksListRowInteraction.action(for: .row, hasLink: true, isMac: true) == .selectRow)
        #expect(TasksListRowInteraction.action(for: .row, hasLink: false, isMac: true) == .selectRow)
        #expect(TasksListRowInteraction.action(for: .row, hasLink: false, isMac: false) == .toggleCompletion)
        #expect(TasksListRowInteraction.action(for: .row, hasLink: true, isMac: false) == nil)
        #expect(TasksListRowInteraction.action(for: .box, hasLink: false, isMac: false) == .toggleCompletion)
    }

    @Test func fourListsShareColumnSelectionAndTaskDetailIsTheRow() throws {
        let tasks = try Self.read("App/Screens/Tasks/TasksView.swift")
        let goals = try Self.read("App/Screens/Goals/GoalsView.swift")
        let mac = try Self.read("App/Navigation/MacNavigation.swift")
        let row = try Self.read("App/Screens/Tasks/TasksListRow.swift")
        #expect(!tasks.contains("Ayrıntıları göster"))
        #expect(tasks.contains(".inkColumnSelection(isSelected: selection == row.id)"))
        #expect(goals.contains(".inkColumnSelection(isSelected: selection?.wrappedValue == goal.id)"))
        #expect(mac.contains(".inkColumnSelection(isSelected: selectedDay == day.id)"))
        #expect(mac.contains(".inkColumnSelection(isSelected: selectedEntity == entity.id)"))
        let menu = try Self.read("App/Screens/Tasks/TaskRowMacChrome.swift")
        #expect(row.contains("TaskRowMacChrome("))
        #expect(row.contains("Button(\"Sil\", systemImage: \"trash\", role: .destructive)"))
        #expect(menu.contains("NSColor.Name(\"InkDanger\")"))
        #expect(menu.contains("rightMouseDown"))
        #expect(menu.contains("acceptsFirstResponder: Bool { false }"))
        let tap = try #require(row.range(of: "struct TasksListRowTap"))
        #expect(!row[..<tap.lowerBound].contains("onTapGesture"))
        #expect(row[tap.lowerBound...].contains("#if os(iOS)"))
        #expect(row[tap.lowerBound...].contains("onTapGesture"))
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private static func repositoryRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
