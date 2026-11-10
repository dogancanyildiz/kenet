import SwiftUI
import VaultFormat

struct ProjectView: View {
    let store: IndexStore
    let name: String
    @State private var actions: TasksModel
    /// Nil until the first query returns; a reload keeps the previous rows until then.
    @State private var tasks: [TaskRow]?
    @State private var detailRow: TaskRow?
    init(store: IndexStore, name: String) {
        self.store = store
        self.name = name
        _actions = State(initialValue: TasksModel(store: store))
    }
    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow(verbatim: name, byline: byline) { SearchButton() }
    }

    /// screens.md: "3 açık · 5 bitti" under the masthead, once the first answer is in.
    private var byline: String? {
        guard let tasks else { return nil }
        let model = ProjectModel(store: store, name: name, tasks: tasks)
        return String(
            format: String(localized: "%1$d açık · %2$d bitti"), model.openCount, model.completed.count)
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
        .taskDetailSheet(store: store, row: $detailRow)
        .task(id: ProjectTasksRequest(name: name, updated: store.lastUpdated)) {
            if let loaded = try? await store.computeProjectTasks(name) { tasks = loaded }
        }
    }

    @ViewBuilder private func sections(_ model: ProjectModel) -> some View {
        // Progress card: completed / (open + completed); cancelled tasks stay out of the ratio.
        let total = model.openCount + model.completed.count
        Section {
            InkCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("İlerleme").font(.ink.section).foregroundStyle(.ink.text)
                        Spacer()
                        Text(String(format: String(localized: "%1$d/%2$d görev"), model.completed.count, total))
                            .font(.ink.value).monospacedDigit().foregroundStyle(.ink.secondaryText)
                    }
                    InkProgress(kind: .fraction(total == 0 ? 0 : Double(model.completed.count) / Double(total)))
                }
            }
            .accessibilityElement(children: .combine)
            .inkListRow()
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
        if !model.entities.isEmpty {
            Section {
                SectionHeader(title: String(localized: "Kişiler ve Konumlar"))
                    .inkListRow()
                ForEach(model.entities) { entity in
                    NavigationLink {
                        EntityView(store: store, entity: entity)
                    } label: {
                        EntityRow(entity: entity)
                            // The 36 pt badge row is shorter than the 44 pt touch target.
                            .frame(minHeight: TapTarget.minimumLength)
                            .contentShape(Rectangle())
                    }
                    .inkListRow()
                }
            }
        }
        // screens.md: related days come last, newest first; a row opens that day.
        if !model.relatedDays.isEmpty {
            Section {
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
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, InkSpacing.cardPadding)
                                .frame(minHeight: TapTarget.minimumLength)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < model.relatedDays.count - 1 { InkCardDivider() }
                        }
                    }
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
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            TasksListRow(
                store: store, row: row, day: actions.day,
                isOverdue: row.due.map { $0 < actions.day } ?? false,
                isBusy: actions.busy.contains(row.id), allowsReopening: true,
                openDetail: { detailRow = row }
            ) { Task { await actions.toggle(row) } }
            .inkListRow(cardSegment: .position(index, of: rows.count))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }
}
