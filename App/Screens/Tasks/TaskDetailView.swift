import SwiftUI

struct TaskDetailView: View {
    let store: IndexStore
    let row: TaskRow
    let openDay: (String) -> Void

    var body: some View {
        List {
            Section {
                LinkedTextView(text: row.text, store: store)
                    .font(.ink.content)
                    .foregroundStyle(.ink.text)
                    .listRowBackground(Color.clear)
            } header: {
                SectionHeader(title: String(localized: "Görev"))
            }
            Section {
                if let date = row.start {
                    field("Başlangıç tarihi") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                    }
                }
                if let date = row.due {
                    field("Bitiş tarihi") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                    }
                }
                if let date = row.done {
                    field("Tamamlanma tarihi") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                    }
                }
                if let priority = row.priority {
                    field("Öncelik") {
                        HStack(spacing: 8) {
                            TaskBox(
                                state: TaskBoxState(
                                    status: KanbanModel.status(of: row), priority: priority))
                            Text(verbatim: VoiceOverCopy.priorityValue(priority))
                                .font(.ink.value)
                        }
                    }
                }
                if let project = row.project {
                    field("Proje") { Text(verbatim: project).font(.ink.content) }
                }
            }
            let entities = store.content.entities.filter { row.linkedFiles.contains($0.id) }
            if !entities.isEmpty {
                Section {
                    ForEach(entities) { entity in
                        NavigationLink {
                            EntityView(store: store, entity: entity)
                        } label: {
                            EntityRow(entity: entity)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    SectionHeader(title: String(localized: "Bağlantılı varlıklar"))
                }
            }
            Section {
                field("Dosya") {
                    Text(verbatim: row.file)
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                if row.createdDate != nil {
                    Button("Kaynak güne git") { openDay(row.file) }
                        .buttonStyle(InkTextButtonStyle())
                        .listRowBackground(Color.clear)
                }
            } header: {
                SectionHeader(title: String(localized: "Kaynak"))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .inkPage()
        .inkPageColumn()
        .navigationTitle("Görev")
        .toolbar { SearchButton() }
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
        .listRowBackground(Color.clear)
    }
}
