import SwiftUI
import VaultFormat

struct TaskTimelineView: View {
    @State private var model: TimelineModel
    @State private var selected: TaskRow?
    @State private var editor: TimelineDateSelection?
    @State private var sourceDay: CalendarDate?
    @State private var todayRequest = UUID()
    let showsFilters: Bool
    let openDay: (String) -> Void

    init(tasks: TasksModel, showsFilters: Bool = false, openDay: @escaping (String) -> Void = { _ in }) {
        _model = State(initialValue: TimelineModel(tasks: tasks))
        self.showsFilters = showsFilters
        self.openDay = openDay
    }
    var body: some View {
        VStack(spacing: 0) {
            controls
            if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red).padding(.horizontal) }
            #if os(macOS)
                HStack(spacing: 0) {
                    TimelineDesktopView(model: model, todayRequest: todayRequest) {
                        selected = $0
                    } edit: {
                        editor = TimelineDateSelection(row: $0, edge: $1, root: model.store.vaultURL)
                    }
                    if let row = selectedTask {
                        Divider()
                        VStack {
                            HStack {
                                Spacer()
                                Button("Kapat", systemImage: "xmark") { selected = nil }.labelStyle(.iconOnly)
                            }.padding()
                            NavigationStack { TaskDetailView(store: model.store, row: row, openDay: openDay) }
                        }.frame(width: 340)
                    }
                }
            #else
                mobileList.sheet(item: $selected) { selection in
                    NavigationStack {
                        if let row = model.store.content.tasks.first(where: { $0.id == selection.id }) {
                            TaskDetailView(store: model.store, row: row) { path in
                                sourceDay = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                            }
                            .navigationDestination(item: $sourceDay) { DayView(store: model.store, date: $0) }
                            .toolbar { Button("Kapat") { selected = nil } }
                        }
                    }.presentationDetents([.medium, .large])
                }
            #endif
        }
        .navigationTitle("Zaman çizelgesi")
        .sheet(item: $editor) { selection in
            NavigationStack { TimelineDateEditor(model: model, selection: selection) }
                .frame(minWidth: 320, minHeight: 200).presentationDetents([.medium, .large])
        }
        .onChange(of: model.store.vaultURL) { _, _ in
            model.clearInteraction()
            selected = nil
            editor = nil
            sourceDay = nil
        }
        .onChange(of: selected?.id) { _, _ in sourceDay = nil }
    }
    private var selectedTask: TaskRow? { model.store.content.tasks.first { $0.id == selected?.id } }
    private var controls: some View {
        HStack {
            #if os(macOS)
                Picker("Gruplama", selection: $model.grouping) {
                    Text("Proje").tag(TimelineModel.Grouping.project)
                    Text("Kişi").tag(TimelineModel.Grouping.person)
                    Text("Yok").tag(TimelineModel.Grouping.none)
                }.pickerStyle(.menu)
            #endif
            Picker("Ölçek", selection: $model.scale) {
                Text("Hafta").tag(TimelineModel.Scale.week)
                Text("Ay").tag(TimelineModel.Scale.month)
                Text("Çeyrek").tag(TimelineModel.Scale.quarter)
            }.pickerStyle(.menu)
            Spacer()
            #if os(iOS)
                Button {
                    model.shiftWindow(by: -model.scale.daysAcross)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Önceki dönem")
                Button {
                    model.shiftWindow(by: model.scale.daysAcross)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Sonraki dönem")
            #endif
            Button("Bugün") {
                model.showToday()
                todayRequest = UUID()
            }
            if showsFilters { TaskFiltersMenu(model: model.tasks) }
        }.padding()
    }
    private var mobileList: some View {
        List {
            ForEach(model.mobileGroups) { group in
                Section {
                    ForEach(group.rows) { row in taskRow(row) }
                } header: {
                    if let date = CalendarDate(group.id) {
                        Text(LocalDay.instant(for: date), format: .dateTime.month(.wide).year().day())
                    }
                }
            }
            if !model.undated.isEmpty {
                Section("Tarihsiz") { ForEach(model.undated) { row in taskRow(row) } }
            }
            if model.mobileGroups.isEmpty && model.undated.isEmpty { Text("Görev yok.").foregroundStyle(.secondary) }
        }
    }
    private func taskRow(_ row: TaskRow) -> some View {
        TimelineTaskRow(model: model, row: row) {
            selected = row
        } edit: {
            editor = TimelineDateSelection(row: row, edge: $0, root: model.store.vaultURL)
        }
    }
}
