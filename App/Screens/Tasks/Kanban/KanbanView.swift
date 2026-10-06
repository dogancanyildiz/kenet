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
                            .toolbar { Button("Kapat") { selectedRow = nil } }
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
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.vertical, 10)
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
