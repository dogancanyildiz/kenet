import SwiftUI

struct TaskDetailView: View {
    let store: IndexStore
    let row: TaskRow
    let openDay: (String) -> Void

    var body: some View {
        List {
            InkPageTitleRow("Görev") { SearchButton() }
            Section {
                SectionHeader(title: String(localized: "Görev"))
                    .inkListRow()
                LinkedTextView(text: row.text, store: store)
                    .font(.ink.content)
                    .foregroundStyle(.ink.text)
                    .inkListRow()
            }
            Section {
                if let date = row.start {
                    field("Başlangıç tarihi") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                    }
                    .inkListRow()
                }
                if let date = row.due {
                    field("Bitiş tarihi") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                    }
                    .inkListRow()
                }
                if let date = row.done {
                    field("Tamamlanma tarihi") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                    }
                    .inkListRow()
                }
                if let priority = row.priority {
                    field("Öncelik") {
                        HStack(spacing: 8) {
                            TaskBox(
                                state: TaskBoxState(
                                    status: KanbanModel.status(of: row), priority: priority),
                                isDecorative: true)
                            Text(verbatim: VoiceOverCopy.priorityValue(priority))
                                .font(.ink.value)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text(verbatim: VoiceOverCopy.priorityValue(priority)))
                    .inkListRow()
                }
                if let project = row.project {
                    field("Proje") { Text(verbatim: project).font(.ink.content) }
                        .inkListRow()
                }
            }
            let entities = store.content.entities.filter { row.linkedFiles.contains($0.id) }
            if !entities.isEmpty {
                Section {
                    SectionHeader(title: String(localized: "Bağlantılı varlıklar"))
                        .inkListRow()
                    ForEach(entities) { entity in
                        NavigationLink {
                            EntityView(store: store, entity: entity)
                        } label: {
                            EntityRow(entity: entity)
                        }
                        .inkListRow()
                    }
                }
            }
            Section {
                SectionHeader(title: String(localized: "Kaynak"))
                    .inkListRow()
                field("Dosya") {
                    Text(verbatim: row.file)
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                .inkListRow()
                if row.createdDate != nil {
                    Button("Kaynak güne git") { openDay(row.file) }
                        .buttonStyle(InkTextButtonStyle())
                        .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .inkPageNavigationTitle("Görev")
    }

    private func field<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value)
        -> some View
    {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
            Spacer(minLength: 8)
            value()
                .foregroundStyle(.ink.text)
                .multilineTextAlignment(.trailing)
        }
    }
}
