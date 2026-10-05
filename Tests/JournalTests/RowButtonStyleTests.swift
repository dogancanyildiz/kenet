import Foundation
import Testing

/// A SwiftUI `List` or `Form` row runs every bordered button it contains on a single tap.
/// These views put more than one button in a row, so each must opt out with `.buttonStyle(.borderless)`.
struct RowButtonStyleTests {
    @Test(arguments: [
        "App/Screens/Days/DaysCalendarView.swift",
        "App/Screens/Entities/EntityAliasesEditor.swift",
        "App/Screens/Entities/EntityFieldEditor.swift",
        "App/Screens/Entities/EntityScalarEditor.swift",
        "App/Screens/Settings/DiagnosticsView.swift",
        "App/Screens/Goals/GoalValueEditor.swift",
        "App/Screens/Entities/UnseenPeopleSection.swift",
    ])
    func multiButtonRowsStayBorderless(_ path: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        #expect(source.contains(".buttonStyle(.borderless)"), "\(path) has several buttons in one list row")
    }
}
