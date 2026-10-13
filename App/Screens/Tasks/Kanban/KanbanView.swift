import SwiftUI
import VaultFormat

struct KanbanView: View {
    @State private var model: KanbanModel
    @Environment(\.shellKind) private var shellKind
    @State private var availableWidth: CGFloat = 0
    @State private var selectedRow: TaskRow?
    @State private var sourceDay: CalendarDate?
    @State private var selectionAnswer = TaskSelectionAnswer()
    /// `true` when the Mac shell hosts the board full-width (outside ``TasksView``).
    let showsFilters: Bool
    let openDay: (String) -> Void

    init(
        tasks: TasksModel, showsFilters: Bool = false, selection: TaskRow? = nil,
        openDay: @escaping (String) -> Void = { _ in }
    ) {
        _selectedRow = State(initialValue: selection)
        _model = State(initialValue: KanbanModel.board(for: tasks))
        self.showsFilters = showsFilters
        self.openDay = openDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TasksPageTop(tasks: model.tasks, current: .kanban) {
                boardOptions
            } menu: {
                groupingMenu
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .padding(.horizontal, InkSpacing.margin)
            }
            #if os(macOS)
                boardWithPanel
            #else
                Group {
                    if usesPanel { boardWithPanel } else { board }
                }
                .sheet(
                    item: Binding(
                        get: { availableWidth > 0 && !usesPanel ? selectedRow : nil },
                        set: { if !usesPanel { selectedRow = $0 } })
                ) { selection in
                    NavigationStack {
                        if let row = selectionAnswer.row(for: selection.id, listed: selection) {
                            TaskDetailView(store: model.store, row: row) { path in
                                sourceDay = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                            }
                            .navigationDestination(item: $sourceDay) { day in
                                DayView(store: model.store, date: day)
                            }
                            .inkSheet("Görev", onClose: { selectedRow = nil })
                        }
                    }.inkAdaptiveSheetPresentation()
                }
            #endif
        }
        .background(Color.ink.paper)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
        .modifier(OptionalNavigationTitle(showsFilters ? "Kanban" : nil))
        .onChange(of: model.store.vaultURL) { _, _ in
            model.tasks.clearFilters()
            selectedRow = nil
            sourceDay = nil
            model.clearDrags()
        }
        .onChange(of: selectedRow?.id) { _, _ in sourceDay = nil }
        .onChange(of: model.grouping) { _, _ in model.clearDrags() }
        .task(id: model.request) { await model.load() }
        .task(id: TaskSelectionRequest(id: selectedRow?.id, updated: model.store.lastUpdated)) {
            let request = TaskSelectionRequest(id: selectedRow?.id, updated: model.store.lastUpdated)
            if let answer = await TaskSelectionAnswer.load(request, store: model.store) { selectionAnswer = answer }
        }
    }

    private var usesPanel: Bool {
        KanbanDetailPlacement.usesPanel(shell: shellKind, width: availableWidth)
    }

    private var boardWithPanel: some View {
        HStack(spacing: 0) {
            board
            if let row = selectedTask {
                Divider().overlay(Color.ink.rule)
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            selectedRow = nil
                        } label: {
                            Label("Kapat", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                                .tapTarget()
                        }
                        .buttonStyle(InkTextButtonStyle())
                    }.padding()
                    NavigationStack {
                        TaskDetailView(store: model.store, row: row, openDay: openDay)
                            // The panel's close row is its bar; the stack never pushes (a day
                            // opens in the shell), so iOS draws no empty system bar above the manşet.
                            .kanbanPanelBar()
                    }
                }.frame(width: KanbanDetailPlacement.panelWidth)
            }
        }
    }

    private var selectedTask: TaskRow? {
        selectionAnswer.row(for: selectedRow?.id, listed: selectedRow)
    }

    /// Show-cancelled toggle. Same header menu as the other pages; the menu sizes to its content.
    private var boardOptions: some View {
        InkHeaderMenu(
            "Pano seçenekleri", systemImage: "slider.horizontal.3", isActive: model.showsCancelled,
            identifier: "tasks.kanban.options"
        ) {
            Toggle("İptal edilenleri göster", isOn: $model.showsCancelled)
        }
    }

    /// Second layer of the view selector: how the board is split into columns.
    /// Mac hugs the label (``KanbanMenuLayout/groupingMenuExpands``): a stretched label makes
    /// the system menu open at the window width.
    private var groupingMenu: some View {
        InkLabeledMenu(
            "Grupla", selection: Binding(get: { model.grouping }, set: { model.choose($0) }),
            options: [
                InkMenuOption("Durum", value: KanbanModel.Grouping.status),
                InkMenuOption("Proje", value: KanbanModel.Grouping.project),
                InkMenuOption("Kişi", value: KanbanModel.Grouping.person),
            ], expands: KanbanMenuLayout.groupingMenuExpands, identifier: TasksViewSelector.menuIdentifier
        )
    }

    private var board: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: KanbanBoardLayout.columnSpacing) {
                    // No columns until the first answer: an empty board must not show while it loads.
                    ForEach(model.rows == nil ? [] : model.columns) { column in
                        KanbanColumnView(model: model, column: column) { selectedRow = $0 }
                            #if os(macOS)
                                .frame(
                                    width: KanbanBoardLayout.columnWidth(
                                        fitting: geometry.size.width, columns: model.columns.count)
                                )
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: KanbanColumnWidthPreference.self, value: [proxy.size.width])
                                    }
                                }
                            #else
                                .frame(width: max(240, min(360, max(0, geometry.size.width - 32))))
                            #endif
                            .frame(height: max(0, geometry.size.height - 24))
                    }
                }
                .scrollTargetLayout().padding(KanbanBoardLayout.boardPadding)
            }
            #if os(iOS)
                .scrollTargetBehavior(.viewAligned)
            #endif
        }
    }
}

extension View {
    @ViewBuilder fileprivate func kanbanPanelBar() -> some View {
        #if os(iOS)
            toolbar(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }
}

/// Where the selected task's detail goes (unit-tested). Mac: always the panel. The split iOS
/// shell: the panel while a column at its floor still fits beside it, otherwise the sheet. Tabs:
/// the sheet.
enum KanbanDetailPlacement {
    static let panelWidth: CGFloat = 340
    /// The phone column's floor plus the board's horizontal padding (`board`: `width - 32`).
    static let minimumBoardWidth: CGFloat = KanbanBoardLayout.minimumColumnWidth + 32

    static func usesPanel(shell: ShellKind, width: CGFloat) -> Bool {
        shell == .split && width >= panelWidth + minimumBoardWidth
    }
}
