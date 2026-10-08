#if os(macOS)
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

    extension View {
        /// Width of the sidebar column (`docs/design.md`, "Biçim").
        func macSidebarColumn() -> some View {
            navigationSplitViewColumnWidth(
                min: InkSpacing.macSidebarMinWidth, ideal: InkSpacing.macSidebarIdealWidth,
                max: InkSpacing.macSidebarMaxWidth)
        }

        /// Width of the list column between the sidebar and the detail.
        func macListColumn() -> some View {
            navigationSplitViewColumnWidth(
                min: InkSpacing.macListMinWidth, ideal: InkSpacing.macListIdealWidth,
                max: InkSpacing.macListMaxWidth)
        }

        /// Smallest size of the journal window: sidebar, list column and a readable detail.
        func macMainWindowMinimumSize() -> some View {
            frame(minWidth: InkSpacing.macWindowMinWidth, minHeight: InkSpacing.macWindowMinHeight)
        }

        /// The window's one search button. Applied to the detail column, so it sits at the
        /// trailing edge of the toolbar whatever is selected.
        func macSearchToolbar() -> some View {
            toolbar {
                // The toolbar shows no title, and without one macOS packs its items at the leading
                // edge; the flexible space keeps search at the trailing edge.
                ToolbarSpacer(.flexible, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) { SearchButton() }
            }
        }
    }
#endif
