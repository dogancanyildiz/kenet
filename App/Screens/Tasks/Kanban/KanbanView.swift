import SwiftUI
import VaultFormat

struct KanbanView: View {
    @State private var model: KanbanModel
    @State private var selectedRow: TaskRow?
    @State private var sourceDay: CalendarDate?
    /// `true` when the Mac shell hosts the board full-width (outside ``TasksView``).
    let showsFilters: Bool
    let openDay: (String) -> Void

    init(tasks: TasksModel, showsFilters: Bool = false, openDay: @escaping (String) -> Void = { _ in }) {
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
                            NavigationStack { TaskDetailView(store: model.store, row: row, openDay: openDay) }
                        }.frame(width: 340)
                    }
                }
            #else
                board.sheet(item: $selectedRow) { selection in
                    NavigationStack {
                        if let row = model.store.content.tasks.first(where: { $0.id == selection.id }) {
                            TaskDetailView(store: model.store, row: row) { path in
                                sourceDay = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                            }
                            .navigationDestination(item: $sourceDay) { day in
                                DayView(store: model.store, date: day)
                            }
                            .inkSheet("Görev", onClose: { selectedRow = nil })
                        }
                    }.presentationDetents([.medium, .large])
                }
            #endif
        }
        .background(Color.ink.paper)
        .modifier(OptionalNavigationTitle(showsFilters ? "Kanban" : nil))
        .onChange(of: model.store.vaultURL) { _, _ in
            model.tasks.clearFilters()
            selectedRow = nil
            sourceDay = nil
            model.clearDrags()
        }
        .onChange(of: selectedRow?.id) { _, _ in sourceDay = nil }
        .onChange(of: model.grouping) { _, _ in model.clearDrags() }
    }

    private var selectedTask: TaskRow? {
        model.store.content.tasks.first { $0.id == selectedRow?.id }
    }

    /// Show-cancelled toggle. On Mac the shared header menu's button-style popup is as wide as
    /// the width offered to the control and, pinned to the trailing icon, runs off the window.
    /// ``KanbanMacOptionsMenu`` opens a content-sized menu that stays inside the window.
    @ViewBuilder private var boardOptions: some View {
        #if os(macOS)
            KanbanMacOptionsMenu(showsCancelled: $model.showsCancelled)
        #else
            InkHeaderMenu(
                "Pano seçenekleri", systemImage: "slider.horizontal.3", isActive: model.showsCancelled,
                identifier: "tasks.kanban.options"
            ) {
                Toggle("İptal edilenleri göster", isOn: $model.showsCancelled)
            }
        #endif
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
                    ForEach(model.columns) { column in
                        KanbanColumnView(model: model, column: column) { selectedRow = $0 }
                            #if os(macOS)
                                .frame(
                                    width: KanbanBoardLayout.columnWidth(
                                        fitting: geometry.size.width, columns: model.columns.count))
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
