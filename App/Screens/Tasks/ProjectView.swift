import SwiftUI
import VaultFormat

struct ProjectView: View {
    let store: IndexStore
    let name: String
    @State private var actions: TasksModel
    /// Nil until the first query returns; a reload keeps the previous rows until then.
    @State private var tasks: [TaskRow]?
    @State private var detailRow: TaskRow?
    @State private var detailSourceDay: CalendarDate?
    init(store: IndexStore, name: String) {
        self.store = store
        self.name = name
        _actions = State(initialValue: TasksModel(store: store))
    }
    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow(verbatim: name) { SearchButton() }
    }

    var body: some View {
        List {
            InkScrolledMasthead(masthead)
            // The page's sections wait for the first answer: no count reads 0 while it loads.
            if let tasks { sections(ProjectModel(store: store, name: name, tasks: tasks)) }
            if let error = actions.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.ink.paper)
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .inkPinnedMasthead(masthead)
        .inkPageNavigationTitle(verbatim: name)
        .sheet(item: $detailRow) { row in
            NavigationStack {
                TaskDetailView(store: store, row: row) { path in
                    detailSourceDay = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                }
                .navigationDestination(item: $detailSourceDay) { DayView(store: store, date: $0) }
                .inkSheet("Görev", onClose: { detailRow = nil })
            }
            .inkAdaptiveSheetPresentation()
        }
        .task(id: ProjectTasksRequest(name: name, updated: store.lastUpdated)) {
            if let loaded = try? await store.computeProjectTasks(name) { tasks = loaded }
        }
    }

    @ViewBuilder private func sections(_ model: ProjectModel) -> some View {
        Section {
            InkCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(verbatim: name).font(.ink.section).foregroundStyle(.ink.text)
                        Spacer()
                        Text(String(format: String(localized: "%1$d açık · %2$d bitti"),
                                    model.openCount, model.completed.count))
                            .font(.ink.meta).foregroundStyle(.ink.secondaryText)
                    }
                    InkProgress(kind: .fraction(
                        model.tasks.isEmpty ? 0 : Double(model.completed.count) / Double(model.tasks.count)))
                }
            }
            .inkListRow()
            if !model.relatedDays.isEmpty {
                SectionHeader(title: String(localized: "İlgili günler"), count: model.relatedDays.count)
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(model.relatedDays.enumerated()), id: \.element) { index, day in
                            NavigationLink {
                                DayView(store: store, date: day)
                            } label: {
                                HStack {
                                    Text(LocalDay.instant(for: day), format: .dateTime.day().month(.abbreviated).year())
                                        .font(.ink.content).foregroundStyle(.ink.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.ink.meta).foregroundStyle(.ink.tertiaryText)
                                }
                                .padding(.horizontal, InkSpacing.cardPadding)
                                .frame(minHeight: TapTarget.minimumLength)
                            }
                            .buttonStyle(.plain)
                            if index < model.relatedDays.count - 1 { InkCardDivider() }
                        }
                    }
                }
                .inkListRow()
            }
            if let day = model.lastActivity {
                labeled("Son etkinlik") {
                    Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
                        .font(.ink.value)
                        .foregroundStyle(.ink.text)
                }
                .inkListRow()
            }
        }
        ForEach(model.openGroups) { group in
            Section {
                SectionHeader(title: groupHeading(group.date), count: group.rows.count)
                    .inkListRow()
                rows(group.rows)
            }
        }
        Section {
            SectionHeader(title: String(localized: "Tamamlanan"), count: model.completed.count)
                .inkListRow()
            rows(model.completed)
        }
        Section {
            SectionHeader(title: String(localized: "Kişiler ve Konumlar"))
                .inkListRow()
            ForEach(model.entities) { entity in
                NavigationLink {
                    EntityView(store: store, entity: entity)
                } label: {
                    EntityRow(entity: entity)
                }
                .inkListRow()
            }
        }
    }

    private func groupHeading(_ day: CalendarDate?) -> String {
        if let day {
            return LocalDay.instant(for: day).formatted(.dateTime.day().month().year())
        }
        return String(localized: "Tarihsiz")
    }

    private func labeled<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value)
        -> some View
    {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
            Spacer(minLength: 8)
            value()
        }
    }

    private func rows(_ rows: [TaskRow]) -> some View {
        ForEach(rows) { row in
            TasksListRow(
                store: store, row: row, day: actions.day,
                isOverdue: row.due.map { $0 < actions.day } ?? false,
                isBusy: actions.busy.contains(row.id), allowsReopening: true,
                openDetail: { detailRow = row }
            ) { Task { await actions.toggle(row) } }
            .inkListRow()
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }
}
