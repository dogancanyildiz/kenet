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
            Section {
                labeled("Açık görevler") {
                    Text(model.openCount.formatted())
                        .font(.ink.value)
                        .foregroundStyle(.ink.text)
                }
                if let day = model.lastActivity {
                    labeled("Son etkinlik") {
                        Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
                            .font(.ink.value)
                            .foregroundStyle(.ink.text)
                    }
                }
            } header: {
                SectionHeader(title: String(localized: "Proje"))
            }
            ForEach(model.openGroups) { group in
                Section {
                    rows(group.rows)
                } header: {
                    SectionHeader(title: groupHeading(group.date), count: group.rows.count)
                }
            }
            Section {
                rows(model.completed)
            } header: {
                SectionHeader(title: String(localized: "Tamamlanan"), count: model.completed.count)
            }
            Section {
                ForEach(model.entities) { entity in
                    NavigationLink {
                        EntityView(store: store, entity: entity)
                    } label: {
                        EntityRow(entity: entity)
                    }
                }
            } header: {
                SectionHeader(title: String(localized: "Kişiler ve Konumlar"))
            }
            if let error = actions.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .inkPage()
        .inkPageColumn()
        .navigationTitle(Text(verbatim: name))
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
        .listRowBackground(Color.clear)
    }

    private func rows(_ rows: [TaskRow]) -> some View {
        ForEach(rows) { row in
            TasksListRow(
                store: store, row: row, day: actions.day,
                isOverdue: row.due.map { $0 < actions.day } ?? false,
                isBusy: actions.busy.contains(row.id), allowsReopening: true
            ) { Task { await actions.toggle(row) } }
            .listRowBackground(Color.ink.paper)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }
}
