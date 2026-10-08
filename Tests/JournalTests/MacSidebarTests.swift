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
            shell.select(.kanban)
            #expect(shell.section == .tasks)
            #expect(shell.tasks.layout == .kanban)
            #expect(shell.layout == .board)
            #expect(shell.sidebarEntry == .kanban)

            shell.select(.timeline)
            #expect(shell.tasks.layout == .timeline)
            #expect(shell.sidebarEntry == .timeline)

            shell.select(.project("mobil"))
            #expect(shell.tasks.layout == .project("mobil"))
            #expect(shell.layout == .columns)
            #expect(shell.sidebarEntry == .project("mobil"))
        }

        @Test func tasksRowReturnsToTheListAndOtherSectionsLeaveTheBoard() {
            var shell = MacShellSelection(section: .today)
            shell.select(.kanban)
            shell.select(.section(.tasks))
            #expect(shell.tasks.layout == .list)
            #expect(shell.tasks.view.listSection == .upcoming)
            #expect(shell.sidebarEntry == .section(.tasks))

            shell.select(.timeline)
            shell.select(.section(.goals))
            #expect(shell.section == .goals)
            #expect(shell.tasks.layout == .list, "coming back to Görevler lands on the list")
            #expect(shell.sidebarEntry == .section(.goals))
        }

        /// Focus goes back to the rebuilt sidebar whenever the choice swapped the layout.
        /// A click and an arrow key ask the same way; the list drops the request if focus is busy.
        @Test func aChoiceThatSwapsTheLayoutAsksForFocus() {
            var shell = MacShellSelection(section: .tasks)
            let asked = [
                shell.select(.kanban),  // columns to board
                shell.select(.timeline),  // board to board: same sidebar
                shell.select(.project("mobil")),  // board to columns
                shell.select(.section(.people)),  // columns to columns
                shell.select(.section(.graph)),  // columns to page
            ]
            #expect(asked == [true, false, true, false, true])
        }

        /// A project deleted from the vault left no row selected and its name on the window.
        @Test func aProjectThatLeftTheVaultFallsBackToTasks() {
            var shell = MacShellSelection(section: .tasks)
            shell.select(.project("mobil"))
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
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MacSidebarKeyboardTests {
        private let watchdog = HostedTestWatchdog()
        @Observable final class Model {
            var shell = MacShellSelection(section: .days)
            var restoresFocus = false
            var note = ""
            /// `nil`: ask the mounted window.
            var focusIsFree: Bool?
            /// The list is built without a check of the test's: the app's own decides, and a
            /// text field outside the split view survives the layout swap.
            var judgesItsOwnWindow = false
            let projects = ["altyapi", "mobil"]
            @ObservationIgnored weak var window: NSWindow?

            var selection: MacSidebarEntry? {
                get { shell.sidebarEntry }
                set {
                    guard let newValue else { return }
                    if shell.select(newValue) { restoresFocus = true }
                }
            }
        }

        /// The shell's shape: a different split view per layout, each with its own sidebar list,
        /// and a text field in the page for the user to move to.
        struct Shell: View {
            @Bindable var model: Model

            var body: some View {
                VStack(spacing: 0) {
                    panes
                    // Outside the split view: the layout swap does not take it away.
                    if model.judgesItsOwnWindow {
                        TextField(String("focus-anchor"), text: $model.note)
                    }
                }
            }

            @ViewBuilder private var panes: some View {
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

            @ViewBuilder private var sidebar: some View {
                let entries = MacSidebar.entries(projects: model.projects)
                if model.judgesItsOwnWindow {
                    MacSidebarList(
                        entries: entries, selection: $model.selection, restoresFocus: $model.restoresFocus)
                } else {
                    MacSidebarList(
                        entries: entries, selection: $model.selection, restoresFocus: $model.restoresFocus,
                        focusIsFree: { [model] in model.focusIsFree ?? MacSidebarFocus.isUnowned(in: model.window) })
                }
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

        /// A choice that swaps the layout while nothing holds the focus (the row that was clicked
        /// went away with the old list): the new sidebar takes it. The request does not ask how
        /// the choice was made; the real click is a step of the Mac screen tour.
        @Test func aChoiceMadeWhileFocusIsFreeGivesItToTheSidebar() async throws {
            let model = Model()
            model.shell = MacShellSelection(section: .tasks)
            let mount = await mount(model)
            defer { mount.close() }
            let first = try #require(sidebarTable(in: mount))
            guard HostedFocus.isAvailable(for: first, in: mount.window) else { return }
            mount.window.makeFirstResponder(nil)

            model.selection = .kanban
            await mount.settle(rounds: 16)
            let table = try #require(sidebarTable(in: mount))
            #expect(
                Self.holdsFocus(table, in: mount.window),
                "focus: \(String(describing: mount.window.firstResponder))")
            #expect(model.restoresFocus == false, "the request is spent once")
        }

        /// The app's own check (no closure handed in). A field of the journal window holds the
        /// keyboard while that window is not the key one; judged by the key window the focus
        /// looked free and the sidebar took it from the field.
        @Test func focusIsJudgedInTheSidebarsWindowNotTheKeyWindow() async throws {
            let model = Model()
            model.shell = MacShellSelection(section: .tasks)
            model.judgesItsOwnWindow = true
            let mount = await mount(model)
            let release = await HostedJournalWindow.claim(mount.window)
            defer {
                release()
                mount.close()
            }
            let field = try #require(Self.anchor(in: mount), "no field outside the split view")
            guard HostedFocus.isAvailable(for: field, in: mount.window) else { return }
            // The hosted window is never ordered on screen, so it is never the key window.
            #expect(NSApp.keyWindow !== mount.window)

            model.selection = .kanban
            await mount.settle(rounds: 16)
            let table = try #require(sidebarTable(in: mount))
            #expect(model.shell.layout == .board)
            #expect(model.restoresFocus == false, "the request was seen")
            #expect(!Self.holdsFocus(table, in: mount.window), "the sidebar took the field's focus")
            #expect(
                Self.isEditing(field, in: mount.window),
                "focus: \(String(describing: mount.window.firstResponder))")
        }

        /// The other half: a field that holds the focus of another window (Settings, a panel)
        /// does not keep the sidebar from taking the free focus of its own window.
        @Test func focusHeldInAnotherWindowDoesNotBlockTheSidebar() async throws {
            let model = Model()
            model.shell = MacShellSelection(section: .tasks)
            model.judgesItsOwnWindow = true
            let mount = await mount(model)
            let release = await HostedJournalWindow.claim(mount.window)
            defer {
                release()
                mount.close()
            }
            let first = try #require(sidebarTable(in: mount))
            guard HostedFocus.isAvailable(for: first, in: mount.window) else { return }
            mount.window.makeFirstResponder(nil)

            let other = Self.window(marked: nil)
            let busy = NSTextField(frame: NSRect(x: 8, y: 8, width: 200, height: 24))
            other.contentView?.addSubview(busy)
            defer { other.contentView = nil }
            guard HostedFocus.isAvailable(for: busy, in: other) else { return }

            model.selection = .kanban
            await mount.settle(rounds: 16)
            let table = try #require(sidebarTable(in: mount))
            #expect(
                Self.holdsFocus(table, in: mount.window),
                "focus: \(String(describing: mount.window.firstResponder))")
        }

        /// Which window the sidebar's focus is judged in: a journal window, the key one of them.
        @Test func sidebarWindowIsAJournalWindowAndTheKeyOneWhenSeveralAreOpen() {
            let settings = Self.window(marked: nil)
            let journal = Self.window(marked: MainWindowMarker.identifier)
            let second = Self.window(marked: MainWindowMarker.identifier)
            let all = [settings, journal, second]
            #expect(MacSidebarFocus.sidebarWindow(among: all, key: settings) === journal)
            #expect(MacSidebarFocus.sidebarWindow(among: all, key: nil) === journal)
            #expect(MacSidebarFocus.sidebarWindow(among: all, key: second) === second)
            #expect(MacSidebarFocus.sidebarWindow(among: [settings], key: settings) == nil)
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

        /// The field that lives outside the split view, so a layout swap does not destroy it.
        private static func anchor(in mount: HostedLayout.Mount) -> NSTextField? {
            mount.views(NSTextField.self).first { field in
                field.isEditable && !Self.insideSplit(field)
            }
        }

        private static func insideSplit(_ view: NSView) -> Bool {
            sequence(first: view, next: { $0.superview }).contains { $0 is NSSplitView }
        }

        /// An offscreen window that is never shown, with or without the journal mark.
        private static func window(marked identifier: NSUserInterfaceItemIdentifier?) -> NSWindow {
            let window = NSWindow(
                contentRect: NSRect(x: -20_000, y: -21_000, width: 240, height: 80),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.identifier = identifier
            return window
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

    /// The selected row's fill stays 10 pt from both edges when a legacy scroller would reserve
    /// a gutter. The test forces that scroller on the hosted list; the process itself keeps the
    /// overlay style (`-AppleShowScrollBars WhenScrolling`).
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct MacSidebarLegacyScrollerTests {
        private let watchdog = HostedTestWatchdog()

        private struct Sidebar: View {
            @State private var selection: MacSidebarEntry? = .section(.tasks)

            var body: some View {
                MacSidebarList(
                    entries: MacSidebar.entries(projects: ["altyapi", "mobil"]),
                    selection: $selection
                )
                .environment(\.appearsActive, true)
            }
        }

        @Test func selectedFillStaysInsetEquallyWhenContentOverflowsUnderALegacyScroller() async throws {
            let width: CGFloat = 208
            let height: CGFloat = 220
            let mount = HostedLayout.Mount(Sidebar(), size: CGSize(width: width, height: height))
            defer { mount.close() }
            mount.window.appearance = NSAppearance(named: .aqua)
            mount.window.contentView?.appearance = NSAppearance(named: .aqua)
            await mount.settle(rounds: 12)

            let scroll = try #require(
                mount.views(NSScrollView.self).first { view in
                    let document = view.documentView?.frame.height ?? 0
                    return document > view.contentView.bounds.height + 8
                }, "the sidebar does not overflow, so a legacy scroller would not take space")
            scroll.scrollerStyle = .legacy
            scroll.layoutSubtreeIfNeeded()
            #expect(scroll.scrollerStyle == .legacy, "the measurement is not the legacy scroller")

            let rep = try Self.bitmap(of: scroll)
            let gaps = try #require(
                Self.fillGaps(in: rep, accent: Self.accent),
                "no selection fill in \(rep.pixelsWide)x\(rep.pixelsHigh)")
            let inset = Int(MacSidebarChrome.fillInset.rounded())
            #expect(
                abs(gaps.left - gaps.right) <= 1,
                "legacy scroller insets \(gaps.left) pt leading and \(gaps.right) pt trailing")
            #expect(abs(gaps.left - inset) <= 1, "leading inset \(gaps.left) pt")
            #expect(abs(gaps.right - inset) <= 1, "trailing inset \(gaps.right) pt")

            let origin = scroll.contentView.bounds.origin.y
            let event = try #require(Self.scrollWheel(down: true))
            scroll.scrollWheel(with: event)
            let moved = abs(scroll.contentView.bounds.origin.y - origin)
            #expect(moved > 1, "wheel scroll moved the sidebar \(moved) pt")
            #expect(
                (scroll.documentView?.frame.height ?? 0) > scroll.contentView.bounds.height + 8,
                "scrolling hid rows instead of moving them")
        }

        private struct Sample {
            var r: CGFloat
            var g: CGFloat
            var b: CGFloat

            func near(_ other: Sample, tolerance: CGFloat = 0.22) -> Bool {
                abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance && abs(b - other.b) <= tolerance
            }
        }

        /// Light accent (`#7A2C6E`); the hosted window is pinned to aqua.
        private static var accent: Sample {
            let hex = InkPalette.Token.accent.variant.hex(for: .light)
            return Sample(
                r: CGFloat((hex >> 16) & 0xFF) / 255,
                g: CGFloat((hex >> 8) & 0xFF) / 255,
                b: CGFloat(hex & 0xFF) / 255)
        }

        private struct Gaps {
            var left: Int
            var right: Int
        }

        /// Widest horizontal run of the fill. Icons are accent-coloured too, and much narrower
        /// than the selected row.
        private static func fillGaps(in rep: NSBitmapImageRep, accent: Sample) -> Gaps? {
            let width = rep.pixelsWide
            var bestLeft = 0
            var bestRight = 0
            var bestSpan = 0
            for y in 0..<rep.pixelsHigh {
                var minX = width
                var maxX = -1
                for x in 0..<width {
                    guard let color = sample(rep, x: x, y: y), color.near(accent) else { continue }
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
                let span = maxX - minX
                if span > bestSpan {
                    bestSpan = span
                    bestLeft = minX
                    bestRight = width - 1 - maxX
                }
            }
            guard bestSpan > width / 2 else { return nil }
            return Gaps(left: bestLeft, right: bestRight)
        }

        private static func bitmap(of view: NSView) throws -> NSBitmapImageRep {
            let width = max(1, Int(view.bounds.width.rounded()))
            let height = max(1, Int(view.bounds.height.rounded()))
            let rep = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = NSSize(width: width, height: height)
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep
        }

        private static func sample(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Sample? {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
            return Sample(r: color.redComponent, g: color.greenComponent, b: color.blueComponent)
        }

        private static func scrollWheel(down: Bool) -> NSEvent? {
            let delta: Int32 = down ? -80 : 80
            guard
                let cg = CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0,
                    wheel3: 0)
            else { return nil }
            return NSEvent(cgEvent: cg)
        }
    }
#endif
