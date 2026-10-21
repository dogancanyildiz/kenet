import Foundation
import Testing

/// Code-placement rules that no headless test can see happen, so they are read from the source
/// (the one place in `JournalTests`, beside the design scanners `ControlPatternUsageTests` and
/// `DesignTokenUsageTests`, that reads source text). Each test name is the rule; behavior that
/// can be measured is measured elsewhere, not here.
struct SourcePatternRuleTests {
    // MARK: - A List row runs every bordered button in it on one tap (iOS)

    /// A SwiftUI `List` or `Form` row runs every bordered button it contains on a single tap.
    /// These views put more than one button in a row, so each must opt out with
    /// `.buttonStyle(.borderless)`. Only a finger on a device shows the double action.
    @Test(arguments: [
        "App/Screens/Days/DaysCalendarView.swift",
        "App/Screens/Entities/EntityAliasesEditor.swift",
        "App/Screens/Entities/EntityFieldEditor.swift",
        "App/Screens/Entities/EntityScalarEditor.swift",
        "App/Screens/Settings/DiagnosticsView.swift",
        "App/Mac/HotKeySettingsView.swift",
        "App/Screens/Goals/GoalValueEditor.swift",
        "App/Screens/Entities/UnseenPeopleSection.swift",
    ])
    func multiButtonListRowsUseBorderlessButtons(_ path: String) throws {
        let source = try Self.read(path)
        #expect(source.contains(".buttonStyle(.borderless)"), "\(path) has several buttons in one list row")
    }

    // MARK: - The 44 pt touch target sits on the button's label (iOS)

    /// `.tapTarget()` grows a control's hit area only on the button's label: frame and content
    /// shape outside a `Button` pad the layout while the hit area stays the label's bounds, so a
    /// layout measurement cannot tell the two apart (`TapTargetTests` measures the size).
    /// These controls were below 44 pt in the Stage 8 audit.
    @Test(arguments: [
        "App/Screens/Today/QuickEntryPlaceholder.swift",
        "App/Screens/Today/QuickEntryTaskControls.swift",
        "App/Design/Components/TaskBox.swift",
        "App/Screens/Days/DaysCalendarView.swift",
        "App/Screens/Summaries/SummariesView.swift",
        "App/Screens/Tasks/Timeline/TaskTimelineView.swift",
        "App/Screens/Graph/GraphControls.swift",
        "App/Design/Components/InkHeaderAction.swift",
        "App/Design/Components/InkTabs.swift",
        "App/Design/Components/InkLabeledMenu.swift",
        "App/Design/Components/InkFilterField.swift",
    ])
    func tapTargetSitsOnTheButtonLabel(_ path: String) throws {
        let source = try Self.read(path)
        #expect(source.contains(".tapTarget()"), "\(path) must expand iOS touch targets to 44 pt")
        // `.buttonStyle` is always applied to the Button, so tapTarget after it is outside.
        #expect(
            !Self.matches(source, #"\.buttonStyle\([^\n]+\)\s*\n\s*\.tapTarget\(\)"#),
            "\(path): .tapTarget() after .buttonStyle is outside the button")
        #expect(
            !Self.matches(
                source,
                #"Button\("[^"]+"(?:,\s*systemImage:\s*"[^"]+")?\)\s*\{[^}]*\}\s*\n(?:\s*\.[^\n]+\n)*\s*\.tapTarget\(\)"#
            ),
            "\(path): .tapTarget() must sit on the label, not after Button(\"…\") { }")
        #expect(
            Self.tapTargetIsInsideLabel(source),
            "\(path): every .tapTarget() must appear inside a label: { … } (or Label / Image label content)")
    }

    /// The scanner itself: a label placement passes, a placement after the button fails.
    @Test func tapTargetRuleTellsALabelFromAnOutsidePlacement() {
        let inside = "Button(action: go) {\n    Image(systemName: \"plus\")\n        .tapTarget()\n}\n"
        let outside = "Button(\"Ekle\") { go() }\n    .buttonStyle(.plain)\n    .tapTarget()\n"
        #expect(Self.tapTargetIsInsideLabel(inside))
        #expect(!Self.tapTargetIsInsideLabel(outside))
        #expect(Self.matches(outside, #"\.buttonStyle\([^\n]+\)\s*\n\s*\.tapTarget\(\)"#))
    }

    // MARK: - Writes the user cannot take back sit behind a confirmation

    /// The task row's "Sil" lives in a context menu, which no offscreen test can open: the menu
    /// item only asks, and the single delete call sits in the confirmation dialog's closure.
    /// (`TasksListRowDeleteTests` measures the confirmation flow itself.)
    @Test func destructiveMenuItemsOnlyAskForConfirmation() throws {
        let source = try Self.read("App/Screens/Tasks/TasksListRow.swift")
        let menuItem = try #require(Self.block(after: "Button(\"Sil\"", in: source))
        #expect(menuItem.contains("deleteConfirmation.request("), "the menu item asks")
        #expect(!menuItem.contains("delete()"), "the menu item deletes without asking")
        let dialog = try #require(Self.block(after: ".destructiveConfirmationDialog(", in: source))
        #expect(dialog.contains("delete()"))
        #expect(source.components(separatedBy: "delete()").count == 2, "a second delete call bypasses the dialog")
    }

    /// The vault preparation writes folders and files into the user's own folder: its primary
    /// action is a page button and nothing in the sheet is bound to Return. Key equivalents do not
    /// reach a window that is never ordered on screen.
    @Test func vaultPreparationBindsNothingToReturn() throws {
        let source = try Self.read("App/Screens/Onboarding/VaultImportView.swift")
        #expect(!source.contains("keyboardShortcut"))
        #expect(!source.contains(".defaultAction"))
    }

    // MARK: - Sheets with unsaved work refuse a swipe-away (iOS)

    /// Swiping a sheet down is an iPhone gesture; the Mac has none, so the binding is read here.
    /// A changed draft (or a vault being written) must not be swiped away without a question.
    @Test(arguments: [
        ["App/Screens/Settings/EntityTypeEditorView.swift", "isDirty"],
        ["App/Screens/Goals/GoalDefinitionForm.swift", "isDirty"],
        ["App/Screens/Onboarding/VaultImportView.swift", "VaultImportChrome.blocksInteractiveDismiss("],
    ])
    func sheetsWithUnsavedWorkRefuseASwipeAway(_ rule: [String]) throws {
        let source = try Self.read(rule[0])
        let call = try #require(Self.call(after: ".interactiveDismissDisabled(", in: source), "\(rule[0])")
        #expect(call.contains(rule[1]), "\(rule[0]): \(call)")
    }

    // MARK: - Touch geometry wired into gestures

    /// A Today/Day task row completes on a tap anywhere in the row: the hit shape must come before
    /// the tap gesture, or taps on the row's empty part fall through. A synthesized click does not
    /// reach SwiftUI gestures in an offscreen window (tried: `sendEvent` leaves the row untouched).
    @Test func dayTaskRowHitShapeComesBeforeItsTapGesture() throws {
        let source = try Self.read("App/Screens/Today/DayTaskView.swift")
        let gesture = try #require(source.range(of: ".onTapGesture"))
        let shape = try #require(
            source.range(
                of: ".contentShape(Rectangle())", options: .backwards, range: source.startIndex..<gesture.lowerBound))
        let between = source[shape.upperBound..<gesture.lowerBound]
        let adjacent = between.allSatisfy { $0.isWhitespace }
        #expect(adjacent, "the hit shape sits right before the tap gesture")
    }

    /// A drag takes hold of a node only near what is drawn; a tap keeps the full tap target
    /// (`GraphMotionTests` and `TapTargetTests` measure both radii). Gestures cannot be driven
    /// offscreen, so their wiring is read here.
    @Test func graphDragUsesTheGrabRadiusAndTapTheHitRadius() throws {
        let source = try Self.read("App/Screens/Graph/GraphCanvas.swift")
        let grab = try #require(Self.call(after: "GraphGrab.begin(", in: source))
        #expect(grab.contains("minimumRadius: Self.minimumGrabRadius"))
        let tap = try #require(Self.block(after: ".onTapGesture", in: source))
        #expect(tap.contains("minimumRadius: Self.minimumHitRadius"))
    }

    // MARK: - Platform actions a test must not run

    /// "Finder'da göster" opens Finder on the machine that runs the test; the button's action is
    /// read instead (`ControlAccessibilityHostedTests` measures that the button is there).
    @Test func finderButtonRevealsTheVault() throws {
        let source = try Self.read("App/Screens/Settings/VaultSettingsView.swift")
        let action = try #require(Self.block(after: "Button(\"Finder'da göster\")", in: source))
        #expect(action.contains("NSWorkspace.shared.activateFileViewerSelecting(["))
    }

    // MARK: - Support

    /// The first `{ … }` block after `marker`, braces balanced.
    private static func block(after marker: String, in source: String) -> String? {
        guard let start = source.range(of: marker),
            let open = source[start.upperBound...].firstIndex(of: "{")
        else { return nil }
        return balanced(source, from: open, open: "{", close: "}")
    }

    /// The argument list of the first call that starts with `marker` (ending in `(`).
    private static func call(after marker: String, in source: String) -> String? {
        guard let start = source.range(of: marker) else { return nil }
        return balanced(source, from: source.index(before: start.upperBound), open: "(", close: ")")
    }

    private static func balanced(_ source: String, from start: String.Index, open: Character, close: Character)
        -> String?
    {
        var depth = 0
        for index in source[start...].indices {
            if source[index] == open { depth += 1 }
            if source[index] == close {
                depth -= 1
                if depth == 0 { return String(source[start...index]) }
            }
        }
        return nil
    }

    /// Each `.tapTarget()` must fall between a `label:` / `Button(action:` label closure and
    /// its matching close, or ride on inline label content that itself sits in that closure.
    private static func tapTargetIsInsideLabel(_ source: String) -> Bool {
        let needle = ".tapTarget()"
        var searchStart = source.startIndex
        while let range = source.range(of: needle, range: searchStart..<source.endIndex) {
            let before = source[source.startIndex..<range.lowerBound]
            // Nearest enclosing `label:` or `Button(action:` … `{` wins over a bare outer Button.
            let labelIdx = before.range(of: "label:", options: .backwards)?.lowerBound
            let actionIdx = before.range(of: "Button(action:", options: .backwards)?.lowerBound
            let opener: String.Index?
            if let labelIdx, let actionIdx {
                opener = max(labelIdx, actionIdx)
            } else {
                opener = labelIdx ?? actionIdx
            }
            guard let opener else { return false }
            let between = source[opener..<range.lowerBound]
            // The tapTarget must still be inside that label closure: more `{` than `}` since opener.
            let opens = between.filter { $0 == "{" }.count
            let closes = between.filter { $0 == "}" }.count
            if opens <= closes { return false }
            searchStart = range.upperBound
        }
        return source.contains(needle)
    }

    private static func matches(_ source: String, _ pattern: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
