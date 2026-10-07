import SwiftUI
import VaultFormat

struct TaskTimelineView: View {
    @State private var model: TimelineModel
    @State private var selected: TaskRow?
    @State private var editor: TimelineDateSelection?
    @State private var sourceDay: CalendarDate?
    @State private var todayRequest = UUID()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// `true` when the Mac shell hosts the timeline full-width (outside ``TasksView``).
    let showsFilters: Bool
    let openDay: (String) -> Void

    init(tasks: TasksModel, showsFilters: Bool = false, openDay: @escaping (String) -> Void = { _ in }) {
        let model = TimelineModel(tasks: tasks)
        model.scale = tasks.viewState.timelineScale
        _model = State(initialValue: model)
        self.showsFilters = showsFilters
        self.openDay = openDay
    }
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
                TasksBoardHeader(tasks: model.tasks, current: .timeline)
                controls
                    .padding(.horizontal, InkSpacing.margin)
                if model.tasks.hasFilters {
                    TaskFilterBand(model: model.tasks)
                        .padding(.horizontal, InkSpacing.margin)
                }
                if let error = model.errorText {
                    InfoBand(kind: .error, verbatim: error)
                        .padding(.horizontal, InkSpacing.margin)
                }
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
                            .inkSheet("Görev", onClose: { selected = nil })
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
        .onChange(of: model.scale) { _, scale in model.tasks.viewState.timelineScale = scale }
        .onAppear {
            // Hosted by the Mac shell: see ``KanbanView``.
            if showsFilters { model.tasks.viewState.mode = .timeline }
        }
    }
    private var selectedTask: TaskRow? { model.store.content.tasks.first { $0.id == selected?.id } }
    /// Second layer of the view selector ("Ölçek") with the period controls on the same row;
    /// they stack at accessibility sizes. Mac also groups the rows.
    private var controls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    scaleMenu(expands: true)
                    #if os(macOS)
                        groupingMenu
                    #endif
                    HStack(spacing: 8) {
                        #if os(iOS)
                            periodButtons
                        #endif
                        todayButton
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 16) {
                    #if os(macOS)
                        scaleMenu(expands: false)
                        groupingMenu
                        Spacer(minLength: 8)
                    #else
                        scaleMenu(expands: true)
                        periodButtons
                    #endif
                    todayButton
                }
            }
        }
    }

    private func scaleMenu(expands: Bool) -> some View {
        InkLabeledMenu(
            "Ölçek", selection: $model.scale,
            options: [
                InkMenuOption("Hafta", value: TimelineModel.Scale.week),
                InkMenuOption("Ay", value: TimelineModel.Scale.month),
                InkMenuOption("Çeyrek", value: TimelineModel.Scale.quarter),
            ], expands: expands, identifier: TasksViewSelector.menuIdentifier)
    }

    #if os(macOS)
        private var groupingMenu: some View {
            InkLabeledMenu(
                "Grupla", selection: $model.grouping,
                options: [
                    InkMenuOption("Proje", value: TimelineModel.Grouping.project),
                    InkMenuOption("Kişi", value: TimelineModel.Grouping.person),
                    InkMenuOption("Yok", value: TimelineModel.Grouping.none),
                ], expands: false, identifier: "tasks.timeline.grouping")
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

    /// The page top is part of the list, so the manşet scrolls away with the rows.
    private var mobileList: some View {
        List {
            InkPageTitleRow("Görevler") {
                TaskFiltersMenu(model: model.tasks)
                SearchButton()
            }
            TasksViewTabs(tasks: model.tasks, current: .timeline)
                .inkListRow()
            controls
                .inkListRow()
            if model.tasks.hasFilters {
                TaskFilterBand(model: model.tasks)
                    .inkListRow()
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
            ForEach(model.mobileGroups) { group in
                Section {
                    if let date = CalendarDate(group.id) {
                        SectionHeader(
                            title: LocalDay.instant(for: date).formatted(
                                .dateTime.month(.wide).year().day()),
                            count: group.rows.count
                        )
                        .inkListRow()
                    }
                    ForEach(group.rows) { row in taskRow(row) }
                }
            }
            if !model.undated.isEmpty {
                Section {
                    SectionHeader(title: String(localized: "Tarihsiz"), count: model.undated.count)
                        .inkListRow()
                    ForEach(model.undated) { row in taskRow(row) }
                }
            }
            if model.mobileGroups.isEmpty && model.undated.isEmpty {
                EmptyState("Görev yok.")
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
    }
    private func taskRow(_ row: TaskRow) -> some View {
        TimelineTaskRow(model: model, row: row) {
            selected = row
        } edit: {
            editor = TimelineDateSelection(row: row, edge: $0, root: model.store.vaultURL)
        }
        .inkListRow()
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
