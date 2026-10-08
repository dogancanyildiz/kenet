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

    /// The real list, mounted offscreen: the system selection walks our rows with the arrow keys.
    @MainActor
    struct MacSidebarKeyboardTests {
        @Observable final class Model {
            var section: DesktopSection? = .days
            var tasks = TasksShellState()
            var restoresFocus = false
            let projects = ["altyapi", "mobil"]

            var selection: MacSidebarEntry? {
                get { MacSidebar.selection(section: section, tasks: tasks.layout) }
                set {
                    guard let newValue else { return }
                    let before = layout
                    switch newValue {
                    case .section(let value):
                        if value == .tasks { tasks.handle(.sidebarTasks) } else { tasks.handle(.sectionLeft) }
                        section = value
                    case .kanban:
                        section = .tasks
                        tasks.handle(.sidebarBoard(.kanban))
                    case .timeline:
                        section = .tasks
                        tasks.handle(.sidebarBoard(.timeline))
                    case .project(let name):
                        section = .tasks
                        tasks.handle(.sidebarProject(name))
                    }
                    if layout != before { restoresFocus = true }
                }
            }

            var layout: MacShellLayout { MacShellLayout.resolve(section: section, tasks: tasks.layout) }
        }

        /// The shell's shape: a different split view per layout, each with its own sidebar list.
        struct Shell: View {
            @Bindable var model: Model

            var body: some View {
                switch model.layout {
                case .columns:
                    NavigationSplitView {
                        sidebar
                    } content: {
                        Text(verbatim: "liste")
                    } detail: {
                        Text(verbatim: "ayrıntı")
                    }
                case .board, .page:
                    NavigationSplitView {
                        sidebar
                    } detail: {
                        Text(verbatim: "pano")
                    }
                }
            }

            private var sidebar: some View {
                MacSidebarList(
                    entries: MacSidebar.entries(projects: model.projects), selection: $model.selection,
                    restoresFocus: $model.restoresFocus)
            }
        }

        @Test func arrowKeysWalkEveryRowIncludingSubEntriesAndStopAtTheEnds() async throws {
            let model = Model()
            let mount = HostedLayout.Mount(Shell(model: model), size: CGSize(width: 900, height: 700))
            defer { mount.close() }
            await mount.settle()
            let entries = MacSidebar.entries(projects: model.projects)

            // Down from "Günlük" through the Tasks group; the split view changes twice on the way.
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
            try await press(.up, in: mount)
            try await press(.up, in: mount)
            try await press(.up, in: mount)
            #expect(model.selection == .timeline)

            // The ends hold.
            for _ in 0..<entries.count { try await press(.up, in: mount) }
            #expect(model.selection == entries.first)
            for _ in 0..<(entries.count + 2) { try await press(.down, in: mount) }
            #expect(model.selection == entries.last)
        }

        @Test func sidebarKeepsKeyboardFocusWhenItsChoiceSwapsTheSplitView() async throws {
            let model = Model()
            model.section = .tasks
            let mount = HostedLayout.Mount(Shell(model: model), size: CGSize(width: 900, height: 700))
            defer { mount.close() }
            await mount.settle()
            let first = try #require(sidebarTable(in: mount))
            #expect(mount.window.makeFirstResponder(first))

            model.selection = .kanban
            await mount.settle(rounds: 24)
            #expect(model.layout == .board)
            let second = try #require(sidebarTable(in: mount))
            #expect(second !== first, "the board has its own sidebar list")
            #expect(
                Self.holdsFocus(second, in: mount.window), "focus: \(String(describing: mount.window.firstResponder))")
            #expect(model.restoresFocus == false, "the request is spent once")
        }

        private enum Arrow { case up, down }

        private func press(_ arrow: Arrow, in mount: HostedLayout.Mount) async throws {
            let table = try #require(sidebarTable(in: mount))
            // The first press puts focus in the list; later ones must find it there already,
            // also in a list the layout change has just built.
            if mount.window.firstResponder === mount.window || mount.window.firstResponder == nil {
                mount.window.makeFirstResponder(table)
            }
            let responder = try #require(mount.window.firstResponder as? NSView)
            #expect(Self.holdsFocus(table, in: mount.window), "arrow key would miss the sidebar")
            let code: UInt16 = arrow == .down ? 125 : 126
            let scalar = arrow == .down ? NSDownArrowFunctionKey : NSUpArrowFunctionKey
            let characters = String(UnicodeScalar(UInt16(scalar))!)
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
                    windowNumber: mount.window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            responder.keyDown(with: event)
            await mount.settle(rounds: 8)
        }

        /// The sidebar is the first table of the split view.
        private func sidebarTable(in mount: HostedLayout.Mount) -> NSTableView? {
            mount.views(NSTableView.self).first
        }

        private static func holdsFocus(_ table: NSTableView, in window: NSWindow) -> Bool {
            guard let responder = window.firstResponder as? NSView else { return false }
            return responder === table || responder.isDescendant(of: table)
        }
    }
#endif
