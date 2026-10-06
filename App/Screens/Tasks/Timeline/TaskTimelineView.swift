import SwiftUI
import VaultFormat

struct TaskTimelineView: View {
    @State private var model: TimelineModel
    @State private var selected: TaskRow?
    @State private var editor: TimelineDateSelection?
    @State private var sourceDay: CalendarDate?
    @State private var todayRequest = UUID()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .padding(.horizontal, InkSpacing.margin)
            }
            #if os(macOS)
                HStack(spacing: 0) {
                    TimelineDesktopView(model: model, todayRequest: todayRequest) {
                        selected = $0
                    } edit: {
                        editor = TimelineDateSelection(row: $0, edge: $1, root: model.store.vaultURL)
                    }
                    if let row = selectedTask {
                        Divider().overlay(Color.ink.rule)
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    selected = nil
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
        .background(Color.ink.paper)
        .modifier(OptionalNavigationTitle(showsFilters ? "Zaman çizelgesi" : nil))
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        #if os(macOS)
                            groupingPicker
                        #endif
                        scalePicker
                    }
                    HStack(spacing: 8) {
                        #if os(iOS)
                            periodButtons
                        #endif
                        todayButton
                        if showsFilters { TaskFiltersMenu(model: model.tasks) }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    #if os(macOS)
                        groupingPicker
                    #endif
                    scalePicker
                    Spacer(minLength: 8)
                    #if os(iOS)
                        periodButtons
                    #endif
                    todayButton
                    if showsFilters { TaskFiltersMenu(model: model.tasks) }
                }
            }
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.vertical, 10)
    }

    private var scalePicker: some View {
        Picker("Ölçek", selection: $model.scale) {
            Text("Hafta").tag(TimelineModel.Scale.week)
            Text("Ay").tag(TimelineModel.Scale.month)
            Text("Çeyrek").tag(TimelineModel.Scale.quarter)
        }
        .pickerStyle(.menu)
        .fixedSize(horizontal: true, vertical: false)
        .lineLimit(1)
    }

    #if os(macOS)
        private var groupingPicker: some View {
            Picker("Gruplama", selection: $model.grouping) {
                Text("Proje").tag(TimelineModel.Grouping.project)
                Text("Kişi").tag(TimelineModel.Grouping.person)
                Text("Yok").tag(TimelineModel.Grouping.none)
            }
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            .lineLimit(1)
        }
    #endif

    private var todayButton: some View {
        Button("Bugün") {
            model.showToday()
            todayRequest = UUID()
        }
        .buttonStyle(InkTextButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .lineLimit(1)
    }

    #if os(iOS)
        private var periodButtons: some View {
            HStack(spacing: 4) {
                Button {
                    model.shiftWindow(by: -model.scale.daysAcross)
                } label: {
                    Image(systemName: "chevron.left")
                        .tapTarget()
                }
                .accessibilityLabel("Önceki dönem")
                .buttonStyle(InkTextButtonStyle())
                Button {
                    model.shiftWindow(by: model.scale.daysAcross)
                } label: {
                    Image(systemName: "chevron.right")
                        .tapTarget()
                }
                .accessibilityLabel("Sonraki dönem")
                .buttonStyle(InkTextButtonStyle())
            }
        }
    #endif

    private var mobileList: some View {
        List {
            ForEach(model.mobileGroups) { group in
                Section {
                    ForEach(group.rows) { row in taskRow(row) }
                } header: {
                    if let date = CalendarDate(group.id) {
                        SectionHeader(
                            title: LocalDay.instant(for: date).formatted(
                                .dateTime.month(.wide).year().day()),
                            count: group.rows.count)
                    }
                }
            }
            if !model.undated.isEmpty {
                Section {
                    ForEach(model.undated) { row in taskRow(row) }
                } header: {
                    SectionHeader(title: String(localized: "Tarihsiz"), count: model.undated.count)
                }
            }
            if model.mobileGroups.isEmpty && model.undated.isEmpty {
                EmptyState("Görev yok.")
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    private func taskRow(_ row: TaskRow) -> some View {
        TimelineTaskRow(model: model, row: row) {
            selected = row
        } edit: {
            editor = TimelineDateSelection(row: row, edge: $0, root: model.store.vaultURL)
        }
        .listRowBackground(Color.ink.paper)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
