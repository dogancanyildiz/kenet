import SwiftUI

/// Which split view the shell shows. The sidebar is rebuilt when this changes, so the shell
/// hands keyboard focus back to it (``MacSidebarList/restoresFocus``).
enum MacShellLayout: Equatable {
    /// Sidebar, list column, detail.
    case columns
    /// Sidebar and a full-width Tasks board.
    case board
    /// Sidebar and a full-width page (summaries, graph, map).
    case page

    static func resolve(section: DesktopSection?, tasks: TasksShellState.Layout) -> Self {
        switch section {
        case .summaries, .graph, .map: return .page
        case .tasks where tasks == .kanban || tasks == .timeline: return .board
        default: return .columns
        }
    }
}

/// What the sidebar selects: the section and, inside "Görevler", the Tasks shell. Pure
/// transitions (unit-tested); the shell view only stores the result.
struct MacShellSelection: Equatable {
    var section: DesktopSection?
    var tasks = TasksShellState()

    var layout: MacShellLayout { MacShellLayout.resolve(section: section, tasks: tasks.layout) }
    var sidebarEntry: MacSidebarEntry? { MacSidebar.selection(section: section, tasks: tasks.layout) }

    /// A choice made in the sidebar (click, arrow key or VoiceOver). Returns whether the
    /// rebuilt sidebar should take the keyboard focus back: when the choice swapped the
    /// layout. The list drops that request if its own window already focuses another control.
    @discardableResult
    mutating func select(_ entry: MacSidebarEntry) -> Bool {
        let before = layout
        switch entry {
        case .section(let value):
            // "Görevler" opens the list on its first section; leaving it resets the board.
            tasks.handle(value == .tasks ? .sidebarTasks : .sectionLeft)
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
        return layout != before
    }

    /// A project that left the vault is no longer a sidebar row: fall back to "Görevler".
    mutating func projectsChanged(_ projects: [String]) {
        guard let project = tasks.project, !projects.contains(project) else { return }
        tasks.handle(.sidebarTasks)
    }
}

extension View {
    /// Width of the sidebar column (`docs/design.md`, "Biçim"); wider on an iPad's three
    /// columns (``ShellStyle/sidebarWidth(tier:dynamicTypeSize:)``).
    func macSidebarColumn() -> some View {
        modifier(SidebarColumnWidth())
    }

    /// Width of the list column between the sidebar and the detail.
    func macListColumn() -> some View {
        navigationSplitViewColumnWidth(
            min: InkSpacing.macListMinWidth, ideal: InkSpacing.macListIdealWidth,
            max: InkSpacing.macListMaxWidth)
    }

    #if os(macOS)
        /// Smallest size of the journal window: sidebar, list column and a readable detail.
        func macMainWindowMinimumSize() -> some View {
            frame(minWidth: InkSpacing.macWindowMinWidth, minHeight: InkSpacing.macWindowMinHeight)
        }
    #endif

    /// The window's one search button. Applied to the detail column, so it sits at the
    /// trailing edge of the toolbar whatever is selected. iOS keeps search in the manşet row
    /// (``SearchButton``), so there this adds nothing.
    @ViewBuilder
    func macSearchToolbar() -> some View {
        #if os(macOS)
            toolbar {
                // The toolbar shows no title, and without one macOS packs its items at the leading
                // edge; the flexible space keeps search at the trailing edge.
                ToolbarSpacer(.flexible, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) { SearchButton() }
            }
        #else
            self
        #endif
    }
}

private struct SidebarColumnWidth: ViewModifier {
    @Environment(\.shellTier) private var tier
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let width = ShellStyle.sidebarWidth(tier: tier, dynamicTypeSize: dynamicTypeSize)
        content.navigationSplitViewColumnWidth(min: width.min, ideal: width.ideal, max: width.max)
    }
}
