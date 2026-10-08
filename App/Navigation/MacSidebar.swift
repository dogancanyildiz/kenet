#if os(macOS)
    import AppKit
    import SwiftUI

    /// Root sections of the Mac sidebar, in sidebar order.
    enum DesktopSection: String, CaseIterable, Identifiable {
        case today, days, tasks, people, places, goals, summaries, graph, map
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .today: "Bugün"
            case .days: "Günlük"
            case .tasks: "Görevler"
            case .people: "Kişiler"
            case .places: "Konumlar"
            case .goals: "Hedefler"
            case .summaries: "Özetler"
            case .graph: "Graph"
            case .map: "Harita"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .days: "book.closed"
            case .tasks: "checklist"
            case .people: "person.2"
            case .places: "mappin.and.ellipse"
            case .goals: "target"
            case .summaries: "chart.bar"
            case .graph: "point.3.connected.trianglepath.dotted"
            case .map: "map"
            }
        }
    }

    /// One selectable sidebar row: a section, a Tasks board or a project.
    enum MacSidebarEntry: Hashable {
        case section(DesktopSection)
        case kanban
        case timeline
        case project(String)

        /// Boards and projects sit one level under "Görevler".
        var isNested: Bool {
            if case .section = self { false } else { true }
        }

        var symbol: String {
            switch self {
            case .section(let section): section.symbol
            case .kanban: "rectangle.split.3x1"
            case .timeline: "chart.bar.xaxis"
            case .project: "folder"
            }
        }

        var title: Text {
            switch self {
            case .section(let section): Text(section.title)
            case .kanban: Text("Kanban")
            case .timeline: Text("Zaman çizelgesi")
            case .project(let name): Text(verbatim: name)
            }
        }
    }

    /// Sidebar content and selection as pure values (unit-tested).
    enum MacSidebar {
        /// Rows top to bottom; the arrow keys walk them in this order, sub-entries included.
        static func entries(projects: [String]) -> [MacSidebarEntry] {
            DesktopSection.allCases.flatMap { section -> [MacSidebarEntry] in
                guard section == .tasks else { return [.section(section)] }
                return [.section(.tasks), .kanban, .timeline] + projects.map(MacSidebarEntry.project)
            }
        }

        /// The one selected row: the section, and inside "Görevler" the row of the open layout.
        static func selection(section: DesktopSection?, tasks: TasksShellState.Layout) -> MacSidebarEntry? {
            guard let section else { return nil }
            guard section == .tasks else { return .section(section) }
            switch tasks {
            case .list: return .section(.tasks)
            case .kanban: return .kanban
            case .timeline: return .timeline
            case .project(let name): return .project(name)
            }
        }
    }

    @MainActor
    enum MacSidebarFocus {
        /// Nothing holds the keyboard focus: no first responder, or the window itself. Reading
        /// the first responder is a query; SwiftUI has no way to ask "is focus anywhere else".
        static func isUnowned(in window: NSWindow?) -> Bool {
            guard let window, let responder = window.firstResponder else { return true }
            return responder === window
        }

        /// The journal window the sidebar lives in (`MainWindowMarker`); the key one when several
        /// are open. A key window elsewhere (Settings, the quick-entry panel) is not it, so it
        /// does not decide whether the sidebar's focus is free.
        static func sidebarWindow(among windows: [NSWindow], key: NSWindow?) -> NSWindow? {
            let journals = windows.filter { $0.identifier == MainWindowMarker.identifier }
            return journals.first { $0 === key } ?? journals.first
        }
    }

    /// Colors of a sidebar row (`docs/design.md`, rule 12): the selected row is filled with the
    /// app accent and written in on-accent ink; in a window that is not key the fill is the rule
    /// tone and the row keeps its ordinary ink.
    enum MacSidebarChrome {
        /// Fill inset from the sidebar edges, like the system selection.
        static let fillInset: CGFloat = 10

        /// `nil`: no fill (a row that is not selected).
        static func fillToken(isSelected: Bool, isWindowActive: Bool) -> InkPalette.Token? {
            guard isSelected else { return nil }
            return isWindowActive ? .accent : .rule
        }

        static func titleToken(isSelected: Bool, isWindowActive: Bool) -> InkPalette.Token {
            isSelected && isWindowActive ? .onAccent : .text
        }

        static func iconToken(isSelected: Bool, isWindowActive: Bool) -> InkPalette.Token {
            isSelected && isWindowActive ? .onAccent : .accent
        }
    }

    /// The sidebar list. Selection stays the system's (arrow keys, focus, VoiceOver "selected");
    /// only its drawing is ours, so the selected row reads in both appearances.
    struct MacSidebarList: View {
        let entries: [MacSidebarEntry]
        @Binding var selection: MacSidebarEntry?
        /// Runs on every click on a row, also when it is already selected.
        var onClick: (MacSidebarEntry) -> Void = { _ in }
        /// Set by the shell when a choice in the sidebar swaps the split view: the new list takes
        /// the keyboard focus the old one had, so the arrow keys keep walking the rows.
        var restoresFocus: Binding<Bool> = .constant(false)
        /// False once focus has gone somewhere else in this sidebar's window (the user clicked
        /// into the page): then the sidebar leaves it there. Focus in another window (Settings,
        /// a panel) does not count.
        var focusIsFree: @MainActor () -> Bool = {
            MacSidebarFocus.isUnowned(
                in: MacSidebarFocus.sidebarWindow(among: NSApp.windows, key: NSApp.keyWindow))
        }
        @Environment(\.appearsActive) private var appearsActive
        @FocusState private var isFocused: Bool

        var body: some View {
            List(selection: $selection) {
                ForEach(entries, id: \.self) { entry in
                    MacSidebarRow(
                        entry: entry, isSelected: selection == entry,
                        isWindowActive: appearsActive
                    )
                    .simultaneousGesture(TapGesture().onEnded { onClick(entry) })
                }
            }
            .listStyle(.sidebar)
            // A legacy scroller (a mouse, with scroll bars set to automatic) reserves its
            // width, so the row background stops short of the trailing edge. The indicator
            // is not drawn; the list still scrolls with the wheel, the trackpad and the arrow keys.
            .scrollIndicators(.never, axes: .vertical)
            .focused($isFocused)
            .macSidebarColumn()
            .task {
                guard restoresFocus.wrappedValue else { return }
                restoresFocus.wrappedValue = false
                // One request, one turn after the list is installed: asked any earlier it is
                // dropped (measured in the app and in the hosted test). It never takes focus
                // from another control.
                isFocused = false
                await Task.yield()
                guard !Task.isCancelled, focusIsFree() else { return }
                isFocused = true
            }
        }
    }

    struct MacSidebarRow: View {
        let entry: MacSidebarEntry
        let isSelected: Bool
        let isWindowActive: Bool

        var body: some View {
            Label {
                entry.title
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(
                        color(MacSidebarChrome.titleToken(isSelected: isSelected, isWindowActive: isWindowActive)))
            } icon: {
                Image(systemName: entry.symbol)
                    .foregroundStyle(
                        color(MacSidebarChrome.iconToken(isSelected: isSelected, isWindowActive: isWindowActive)))
            }
            .padding(.leading, entry.isNested ? InkSpacing.margin : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .focusEffectDisabled()
            .listRowBackground(background)
        }

        private var background: some View {
            RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                .fill(fillStyle)
                .padding(.horizontal, MacSidebarChrome.fillInset)
        }

        private var fillStyle: Color {
            MacSidebarChrome.fillToken(isSelected: isSelected, isWindowActive: isWindowActive).map(color) ?? .clear
        }

        private func color(_ token: InkPalette.Token) -> Color { Color(token.assetName) }
    }
#endif
