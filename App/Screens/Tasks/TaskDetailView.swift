import SwiftUI

struct TaskDetailView: View {
    let store: IndexStore
    let row: TaskRow
    let openDay: (String) -> Void

    var body: some View {
        Form {
            Section("Görev") { LinkedTextView(text: row.text, store: store) }
            if let date = row.due {
                LabeledContent("Bitiş tarihi") {
                    Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                }
            }
            if let date = row.done {
                LabeledContent("Tamamlanma tarihi") {
                    Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                }
            }
            if let priority = row.priority {
                LabeledContent("Öncelik") { Text(verbatim: priority.token) }
            }
            if let project = row.project { LabeledContent("Proje") { Text(verbatim: project) } }
            let entities = store.content.entities.filter { row.linkedFiles.contains($0.id) }
            if !entities.isEmpty {
                Section("Bağlantılı varlıklar") {
                    ForEach(entities) { entity in
                        NavigationLink {
                            EntityView(store: store, entity: entity)
                        } label: {
                            EntityRow(entity: entity)
                        }
                    }
                }
            }
            Section("Kaynak") {
                Text(verbatim: row.file).font(.caption)
                if row.createdDate != nil {
                    Button("Kaynak güne git") { openDay(row.file) }
                }
            }
        }.formStyle(.grouped).navigationTitle("Görev").toolbar { SearchButton() }
    }
}
