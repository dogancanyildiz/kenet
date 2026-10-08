#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Journal

    /// Mac sidebar: one row per entry, one selected row, readable selection, keyboard walk.
    struct MacSidebarModelTests {
        private let projects = ["altyapi", "mobil"]

        @Test func rowsAreFlatAndSubEntriesFollowTasks() {
            let entries = MacSidebar.entries(projects: projects)
            #expect(
                entries == [
                    .section(.today), .section(.days), .section(.tasks), .kanban, .timeline,
                    .project("altyapi"), .project("mobil"), .section(.people), .section(.places),
                    .section(.goals), .section(.summaries), .section(.graph), .section(.map),
                ])
            #expect(Set(entries).count == entries.count, "every row is its own selection value")
            #expect(entries.filter(\.isNested) == [.kanban, .timeline, .project("altyapi"), .project("mobil")])
        }

        @Test func notesHasNoSidebarRow() {
            #expect(DesktopSection.allCases.map(\.rawValue).contains("notes") == false)
            #expect(MacSidebar.entries(projects: []).count == 11)
        }

        /// Audit finding 4: the whole Tasks group was painted as one block.
        @Test(arguments: [
            (TasksShellState.Layout.list, MacSidebarEntry.section(.tasks)),
            (.kanban, .kanban), (.timeline, .timeline), (.project("mobil"), .project("mobil")),
        ])
        func exactlyOneTasksRowIsSelected(layout: TasksShellState.Layout, expected: MacSidebarEntry) {
            let selected = MacSidebar.selection(section: .tasks, tasks: layout)
            #expect(selected == expected)
            let highlighted = MacSidebar.entries(projects: projects).filter { $0 == selected }
            #expect(highlighted.count == 1)
        }

        @Test func otherSectionsSelectTheirOwnRowWhateverTheTasksLayout() {
            for section in DesktopSection.allCases where section != .tasks {
                #expect(MacSidebar.selection(section: section, tasks: .kanban) == .section(section))
            }
            #expect(MacSidebar.selection(section: nil, tasks: .list) == nil)
        }

        @Test func shellLayoutFollowsTheSelectedRow() {
            #expect(MacShellLayout.resolve(section: .today, tasks: .kanban) == .columns)
            #expect(MacShellLayout.resolve(section: .tasks, tasks: .list) == .columns)
            #expect(MacShellLayout.resolve(section: .tasks, tasks: .project("mobil")) == .columns)
            #expect(MacShellLayout.resolve(section: .tasks, tasks: .kanban) == .board)
            #expect(MacShellLayout.resolve(section: .tasks, tasks: .timeline) == .board)
            for section in [DesktopSection.summaries, .graph, .map] {
                #expect(MacShellLayout.resolve(section: section, tasks: .list) == .page)
            }
        }

        // MARK: Selection colors (`docs/design.md` rules 4 and 12)

        @Test func onlyTheSelectedRowIsFilledAndAnInactiveWindowFadesIt() {
            #expect(MacSidebarChrome.fillToken(isSelected: false, isWindowActive: true) == nil)
            #expect(MacSidebarChrome.fillToken(isSelected: false, isWindowActive: false) == nil)
            #expect(MacSidebarChrome.fillToken(isSelected: true, isWindowActive: true) == .accent)
            #expect(MacSidebarChrome.fillToken(isSelected: true, isWindowActive: false) == .rule)
        }

        /// Audit finding 5: white on the dark accent was 2.03:1. Both window states, all four
        /// appearances: text at least 4.5:1, the icon at least 3:1 on the fill the row really has.
        @Test(arguments: InkPalette.Appearance.allCases, [true, false])
        func selectedRowStaysReadableOnItsFill(appearance: InkPalette.Appearance, isWindowActive: Bool) throws {
            let fill = try #require(
                MacSidebarChrome.fillToken(isSelected: true, isWindowActive: isWindowActive)
            ).variant.hex(for: appearance)
            let title = MacSidebarChrome.titleToken(isSelected: true, isWindowActive: isWindowActive)
            let icon = MacSidebarChrome.iconToken(isSelected: true, isWindowActive: isWindowActive)
            let titleRatio = InkPalette.contrastRatio(
                foreground: title.variant.hex(for: appearance), background: fill)
            let iconRatio = InkPalette.contrastRatio(
                foreground: icon.variant.hex(for: appearance), background: fill)
            #expect(titleRatio >= 4.5, "\(title.rawValue) on fill, \(appearance.rawValue): \(titleRatio)")
            #expect(iconRatio >= 3, "\(icon.rawValue) on fill, \(appearance.rawValue): \(iconRatio)")
        }

        @Test func unselectedRowKeepsOrdinaryInkAndAccentIcon() {
            for active in [true, false] {
                #expect(MacSidebarChrome.titleToken(isSelected: false, isWindowActive: active) == .text)
                #expect(MacSidebarChrome.iconToken(isSelected: false, isWindowActive: active) == .accent)
            }
        }
    }

    /// The shell's selection as pure transitions: the same value the shell view stores.
    struct MacShellSelectionTests {
        @Test func boardRowsOpenTheirBoardAndProjectRowsTheirProject() {
            var shell = MacShellSelection(section: .today)
            shell.select(.kanban, byKeyboard: false)
            #expect(shell.section == .tasks)
            #expect(shell.tasks.layout == .kanban)
            #expect(shell.layout == .board)
            #expect(shell.sidebarEntry == .kanban)

            shell.select(.timeline, byKeyboard: false)
            #expect(shell.tasks.layout == .timeline)
            #expect(shell.sidebarEntry == .timeline)

            shell.select(.project("mobil"), byKeyboard: false)
            #expect(shell.tasks.layout == .project("mobil"))
            #expect(shell.layout == .columns)
            #expect(shell.sidebarEntry == .project("mobil"))
        }

        @Test func tasksRowReturnsToTheListAndOtherSectionsLeaveTheBoard() {
            var shell = MacShellSelection(section: .today)
            shell.select(.kanban, byKeyboard: false)
            shell.select(.section(.tasks), byKeyboard: false)
            #expect(shell.tasks.layout == .list)
            #expect(shell.tasks.view.listSection == .upcoming)
            #expect(shell.sidebarEntry == .section(.tasks))

            shell.select(.timeline, byKeyboard: false)
            shell.select(.section(.goals), byKeyboard: false)
            #expect(shell.section == .goals)
            #expect(shell.tasks.layout == .list, "coming back to Görevler lands on the list")
            #expect(shell.sidebarEntry == .section(.goals))
        }

        /// Focus goes back to the rebuilt sidebar only for an arrow key that swapped the layout.
        @Test func onlyAKeyboardChoiceThatSwapsTheLayoutAsksForFocus() {
            var shell = MacShellSelection(section: .tasks)
            let asked = [
                shell.select(.kanban, byKeyboard: true),  // columns to board
                shell.select(.timeline, byKeyboard: true),  // board to board: same sidebar
                shell.select(.project("mobil"), byKeyboard: true),  // board to columns
                shell.select(.section(.people), byKeyboard: true),  // columns to columns
                shell.select(.section(.graph), byKeyboard: true),  // columns to page
            ]
            #expect(asked == [true, false, true, false, true])

            // A click leaves focus to the pointer, whatever it swaps.
            var clicked = MacShellSelection(section: .tasks)
            let afterClicks = [
                clicked.select(.kanban, byKeyboard: false),
                clicked.select(.section(.summaries), byKeyboard: false),
            ]
            #expect(afterClicks == [false, false])
        }

        /// A project deleted from the vault left no row selected and its name on the window.
        @Test func aProjectThatLeftTheVaultFallsBackToTasks() {
            var shell = MacShellSelection(section: .tasks)
            shell.select(.project("mobil"), byKeyboard: false)
            shell.projectsChanged(["altyapi", "mobil"])
            #expect(shell.sidebarEntry == .project("mobil"), "still listed: nothing changes")

            shell.projectsChanged(["altyapi"])
            #expect(shell.sidebarEntry == .section(.tasks))
            #expect(shell.tasks.layout == .list)
            #expect(MacSidebar.entries(projects: ["altyapi"]).contains(shell.sidebarEntry!))

            var other = MacShellSelection(section: .goals)
            other.projectsChanged([])
            #expect(other.sidebarEntry == .section(.goals))
        }
    }

    /// The real list, mounted offscreen: the system selection walks our rows with the arrow keys.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct MacSidebarKeyboardTests {
        private let watchdog = HostedTestWatchdog()
        @Observable final class Model {
            var shell = MacShellSelection(section: .days)
            var restoresFocus = false
            /// What `NSApp.currentEvent` tells the shell in the app.
            var byKeyboard = true
            var note = ""
            /// `nil`: ask the mounted window, as the app asks its key window.
            var focusIsFree: Bool?
            let projects = ["altyapi", "mobil"]
            @ObservationIgnored weak var window: NSWindow?

            var selection: MacSidebarEntry? {
                get { shell.sidebarEntry }
                set {
                    guard let newValue else { return }
                    if shell.select(newValue, byKeyboard: byKeyboard) { restoresFocus = true }
                }
            }
        }

        /// The shell's shape: a different split view per layout, each with its own sidebar list,
        /// and a text field in the page for the user to move to.
        struct Shell: View {
            @Bindable var model: Model

            var body: some View {
                switch model.shell.layout {
                case .columns:
                    NavigationSplitView {
                        sidebar
                    } content: {
                        Text(verbatim: "liste")
                    } detail: {
                        TextField(String("not"), text: $model.note)
                    }
                case .board, .page:
                    NavigationSplitView {
                        sidebar
                    } detail: {
                        TextField(String("not"), text: $model.note)
                    }
                }
            }

            private var sidebar: some View {
                MacSidebarList(
                    entries: MacSidebar.entries(projects: model.projects), selection: $model.selection,
                    restoresFocus: $model.restoresFocus,
                    focusIsFree: { [model] in model.focusIsFree ?? MacSidebarFocus.isUnowned(in: model.window) })
            }
        }

        private func mount(_ model: Model) async -> HostedLayout.Mount {
            let mount = HostedLayout.Mount(Shell(model: model), size: CGSize(width: 900, height: 700))
            model.window = mount.window
            await mount.settle()
            return mount
        }

        @Test func arrowKeysWalkEveryRowIncludingSubEntriesAndStopAtTheEnds() async throws {
            let model = Model()
            let mount = await mount(model)
            defer { mount.close() }
            let entries = MacSidebar.entries(projects: model.projects)
            let first = try #require(sidebarTable(in: mount))
            guard HostedFocus.isAvailable(for: first, in: mount.window) else { return }

            // Down from "Günlük" through the Tasks group. The split view changes twice on the way
            // and nothing but the sidebar itself may put focus back in the new list.
            var walked: [MacSidebarEntry?] = []
            for _ in 0..<6 {
                try await press(.down, in: mount)
                walked.append(model.selection)
            }
            #expect(
                walked == [
                    .section(.tasks), .kanban, .timeline, .project("altyapi"), .project("mobil"),
                    .section(.people),
                ])

            // Up again, back across the board.
            for _ in 0..<3 { try await press(.up, in: mount) }
            #expect(model.selection == .timeline)

            // The ends hold.
            for _ in 0..<entries.count { try await press(.up, in: mount) }
            #expect(model.selection == entries.first)
            for _ in 0..<(entries.count + 2) { try await press(.down, in: mount) }
            #expect(model.selection == entries.last)
        }

        @Test func aKeyboardChoiceThatSwapsTheSplitViewKeepsFocusInTheSidebar() async throws {
            let model = Model()
            model.shell = MacShellSelection(section: .tasks)
            let mount = await mount(model)
            defer { mount.close() }
            let first = try #require(sidebarTable(in: mount))
            guard HostedFocus.isAvailable(for: first, in: mount.window) else { return }

            model.selection = .kanban
            await mount.settle(rounds: 12)
            #expect(model.shell.layout == .board)
            let second = try #require(sidebarTable(in: mount))
            #expect(second !== first, "the board has its own sidebar list")
            #expect(
                Self.holdsFocus(second, in: mount.window),
                "focus: \(String(describing: mount.window.firstResponder))")
            #expect(model.restoresFocus == false, "the request is spent once")
        }

        /// The pointer is on its way to the page: a click on a sidebar row never pulls focus back.
        @Test func aClickedChoiceLeavesFocusAlone() async throws {
            let model = Model()
            model.shell = MacShellSelection(section: .tasks)
            model.byKeyboard = false
            let mount = await mount(model)
            defer { mount.close() }

            model.selection = .kanban
            await mount.settle(rounds: 16)
            let table = try #require(sidebarTable(in: mount))
            #expect(!Self.holdsFocus(table, in: mount.window))
            #expect(model.restoresFocus == false)
        }

        /// Review finding: the sidebar took focus back from a field the user had moved to.
        @Test(arguments: [40, 200])
        func focusTheUserMovedElsewhereStaysThere(afterMilliseconds delay: Int) async throws {
            let model = Model()
            model.shell = MacShellSelection(section: .tasks)
            let mount = await mount(model)
            defer { mount.close() }
            let first = try #require(sidebarTable(in: mount))
            guard HostedFocus.isAvailable(for: first, in: mount.window) else { return }

            model.selection = .kanban
            // The delay counts from the moment the board (and its own sidebar) is installed:
            // a field of the page that is about to go away would prove nothing.
            for _ in 0..<200 {
                mount.window.contentView?.layoutSubtreeIfNeeded()
                if let table = sidebarTable(in: mount), table !== first { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(sidebarTable(in: mount) !== first, "the board was installed")
            try await Task.sleep(for: .milliseconds(delay))
            let target = try #require(
                mount.views(NSTextField.self).first { $0.isEditable }, "the board page has a text field")
            guard HostedFocus.isAvailable(for: target, in: mount.window) else { return }

            await mount.settle(rounds: 24)
            let table = try #require(sidebarTable(in: mount))
            #expect(!Self.holdsFocus(table, in: mount.window), "the sidebar took the focus back")
            #expect(
                Self.isEditing(target, in: mount.window),
                "focus: \(String(describing: mount.window.firstResponder))")
        }

        /// The request is dropped when focus already belongs to something else at that moment.
        @Test func sidebarDoesNotTakeFocusThatIsNotFree() async throws {
            let model = Model()
            model.shell = MacShellSelection(section: .tasks)
            model.focusIsFree = false
            let mount = await mount(model)
            defer { mount.close() }

            model.selection = .kanban
            await mount.settle(rounds: 16)
            let table = try #require(sidebarTable(in: mount))
            #expect(model.restoresFocus == false, "the request was seen")
            #expect(!Self.holdsFocus(table, in: mount.window))
        }

        @Test func focusIsFreeOnlyWhileNothingHoldsIt() async throws {
            let model = Model()
            let mount = await mount(model)
            defer { mount.close() }
            #expect(MacSidebarFocus.isUnowned(in: nil))
            mount.window.makeFirstResponder(nil)
            #expect(MacSidebarFocus.isUnowned(in: mount.window))
            let field = try #require(mount.views(NSTextField.self).first { $0.isEditable })
            guard HostedFocus.isAvailable(for: field, in: mount.window) else { return }
            #expect(!MacSidebarFocus.isUnowned(in: mount.window))
            let table = try #require(sidebarTable(in: mount))
            guard HostedFocus.isAvailable(for: table, in: mount.window) else { return }
            #expect(!MacSidebarFocus.isUnowned(in: mount.window))
        }

        private enum Arrow { case up, down }

        /// Sends the key to whatever holds the keyboard focus, as the window would.
        private func press(_ arrow: Arrow, in mount: HostedLayout.Mount) async throws {
            let table = try #require(sidebarTable(in: mount))
            #expect(Self.holdsFocus(table, in: mount.window), "arrow key would miss the sidebar")
            let responder = try #require(mount.window.firstResponder as? NSView)
            let code: UInt16 = arrow == .down ? 125 : 126
            let scalar = arrow == .down ? NSDownArrowFunctionKey : NSUpArrowFunctionKey
            let characters = String(UnicodeScalar(UInt16(scalar))!)
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
                    windowNumber: mount.window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            responder.keyDown(with: event)
            await mount.settle(rounds: 10)
        }

        /// The sidebar is the first table of the split view.
        private func sidebarTable(in mount: HostedLayout.Mount) -> NSTableView? {
            mount.views(NSTableView.self).first
        }

        private static func holdsFocus(_ table: NSTableView, in window: NSWindow) -> Bool {
            guard let responder = window.firstResponder as? NSView else { return false }
            return responder === table || responder.isDescendant(of: table)
        }

        /// A text field being edited hands the focus to the window's field editor.
        private static func isEditing(_ field: NSTextField, in window: NSWindow) -> Bool {
            if window.firstResponder === field { return true }
            guard let editor = window.firstResponder as? NSText else { return false }
            return editor.delegate === field
        }
    }
#endif
