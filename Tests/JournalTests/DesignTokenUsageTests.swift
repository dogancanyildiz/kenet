import Foundation
import Testing

/// Keeps hex literals and ad-hoc Color(red:) out of App code outside `App/Design`.
/// `.red` / `.orange` scan is allowlisted until screen work lands; the list only shrinks.
struct DesignTokenUsageTests {
    /// Paths under `App/` that still use `.red` or `.orange` (Stage 9 screen jobs clear these).
    private static let systemColorAllowlist: Set<String> = [
        "App/Mac/HotKeySettingsView.swift",
        "App/Navigation/MacNavigation.swift",
        "App/Screens/Entities/EntitiesView.swift",
        "App/Screens/Entities/EntityRenameView.swift",
        "App/Screens/Entities/EntityScalarEditor.swift",
        "App/Screens/Entities/EntityTypedFieldEditor.swift",
        "App/Screens/Entities/EntityView.swift",
        "App/Screens/Entities/UnresolvedEntityView.swift",
        "App/Screens/Onboarding/OnboardingView.swift",
        "App/Screens/Onboarding/VaultImportView.swift",
        "App/Screens/Onboarding/VaultInaccessibleView.swift",
        "App/Screens/Settings/DiagnosticsView.swift",
        "App/Screens/Settings/EntityTypeEditorView.swift",
        "App/Screens/Settings/EntityTypesSettingsView.swift",
        "App/Screens/Settings/GeofenceSettingsView.swift",
        "App/Screens/Shared/SearchNoteView.swift",
        "App/Screens/Shared/SearchView.swift",
        "App/Screens/Shared/SingleLineTextEditor.swift",
        "App/Screens/Summaries/SummariesView.swift",
        "App/Screens/Tasks/EntityOpenTasksView.swift",
        "App/Screens/Today/DayCalendarView.swift",
        "App/Screens/Today/DayEventView.swift",
        "App/Screens/Today/DayTaskView.swift",
        "App/Screens/Today/DayTasksView.swift",
        "App/Screens/Today/DayView.swift",
        "App/Screens/Today/JournalView.swift",
        "App/Screens/Today/QuickEntryPlaceholder.swift",
        "App/Screens/Today/QuickEntryTaskControls.swift",
        "App/Screens/Today/TaskTextEditor.swift",
    ]

    @Test func noHexColorLiteralsOutsideDesign() throws {
        let offenders = try Self.appSwiftFiles().filter { path in
            guard !path.hasPrefix("App/Design/") else { return false }
            let source = try Self.read(path)
            return Self.containsHexLiteral(source) || Self.containsRGBInitializer(source)
        }
        #expect(offenders.isEmpty, "Hex / Color(red:) outside App/Design: \(offenders.sorted())")
    }

    @Test func systemColorAllowlistOnlyShrinks() throws {
        let offenders = try Self.appSwiftFiles().filter { path in
            let source = try Self.read(path)
            return Self.containsSystemColor(source)
        }
        let unexpected = Set(offenders).subtracting(Self.systemColorAllowlist)
        #expect(
            unexpected.isEmpty,
            "New .red/.orange usage outside allowlist: \(unexpected.sorted())")
        let cleared = Self.systemColorAllowlist.subtracting(offenders)
        #expect(
            cleared.isEmpty,
            "Allowlist entries no longer use .red/.orange — remove from list: \(cleared.sorted())")
    }

    // MARK: - Scanning

    private static func containsHexLiteral(_ source: String) -> Bool {
        // #RRGGBB or #RRGGBBAA in string/comment form used as color.
        let pattern = #"#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\b"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }

    private static func containsRGBInitializer(_ source: String) -> Bool {
        source.range(of: #"\bColor\s*\(\s*red\s*:"#, options: .regularExpression) != nil
    }

    private static func containsSystemColor(_ source: String) -> Bool {
        source.range(of: #"\.red\b"#, options: .regularExpression) != nil
            || source.range(of: #"\.orange\b"#, options: .regularExpression) != nil
    }

    private static func appSwiftFiles() throws -> [String] {
        let root = repositoryRoot().appendingPathComponent("App")
        var files: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let relative = url.path.replacingOccurrences(
                of: repositoryRoot().path + "/", with: "")
            files.append(relative)
        }
        return files
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
