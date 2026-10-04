import SwiftUI
import VaultFormat

struct KanbanView: View {
    @State private var model: KanbanModel
    @State private var selectedRow: TaskRow?
    @State private var sourceDay: CalendarDate?
    let showsFilters: Bool
    let openDay: (String) -> Void

    init(tasks: TasksModel, showsFilters: Bool = false, openDay: @escaping (String) -> Void = { _ in }) {
        _model = State(initialValue: KanbanModel(tasks: tasks))
        self.showsFilters = showsFilters
        self.openDay = openDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red).padding(.horizontal) }
            #if os(macOS)
                HStack(spacing: 0) {
                    board
                    if let row = selectedTask {
                        Divider()
                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                Button("Kapat", systemImage: "xmark") { selectedRow = nil }.labelStyle(.iconOnly)
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
                            .toolbar { Button("Kapat") { selectedRow = nil } }
                        }
                    }.presentationDetents([.medium, .large])
                }
            #endif
        }
        .navigationTitle("Kanban")
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

    private var controls: some View {
        HStack {
            Picker("Gruplama", selection: $model.grouping) {
                Text("Durum").tag(KanbanModel.Grouping.status)
                Text("Proje").tag(KanbanModel.Grouping.project)
                Text("Kişi").tag(KanbanModel.Grouping.person)
            }.pickerStyle(.menu)
            Spacer()
            Menu {
                Toggle("İptal edilenleri göster", isOn: $model.showsCancelled)
            } label: {
                Label("Pano seçenekleri", systemImage: "ellipsis.circle")
            }
            if showsFilters { TaskFiltersMenu(model: model.tasks) }
        }.padding()
    }

    private var board: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(model.columns) { column in
                        KanbanColumnView(model: model, column: column) { selectedRow = $0 }
                            #if os(macOS)
                                .frame(width: 300)
                            #else
                                .frame(width: max(240, min(360, geometry.size.width - 32)))
                            #endif
                            .frame(height: geometry.size.height - 24)
                    }
                }
                .scrollTargetLayout().padding(12)
            }
            #if os(iOS)
                .scrollTargetBehavior(.viewAligned)
            #endif
        }
    }
}
