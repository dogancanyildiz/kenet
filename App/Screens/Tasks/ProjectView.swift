import SwiftUI
import VaultFormat

struct ProjectView: View {
    let store: IndexStore
    let name: String
    @State private var actions: TasksModel
    init(store: IndexStore, name: String) {
        self.store = store
        self.name = name
        _actions = State(initialValue: TasksModel(store: store))
    }
    private var model: ProjectModel { ProjectModel(store: store, name: name) }
    var body: some View {
        List {
            InkPageTitleRow(verbatim: name)
            Section {
                SectionHeader(title: String(localized: "Proje"))
                    .inkListRow()
                labeled("Açık görevler") {
                    Text(model.openCount.formatted())
                        .font(.ink.value)
                        .foregroundStyle(.ink.text)
                }
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
            if let error = actions.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.ink.paper)
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageColumn()
        .inkPageNavigationTitle(verbatim: name)
        .toolbar { SearchButton() }
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
                isBusy: actions.busy.contains(row.id), allowsReopening: true
            ) { Task { await actions.toggle(row) } }
            .inkListRow()
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }
}
