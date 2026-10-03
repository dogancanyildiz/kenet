import SwiftUI
import VaultFormat

struct DayTaskView: View {
    let store: IndexStore
    let row: TaskRow
    let isToday: Bool
    let isOverdue: Bool
    let completed: Bool
    let isBusy: Bool
    let complete: () -> Void
    @State private var textEditor: TaskEditorModel?
    @State private var dateEditor: TaskEditorModel?
    @State private var errorText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: complete) {
                Image(systemName: completed || row.isClosed ? "checkmark.square.fill" : "square")
            }
            .accessibilityLabel("Görevi tamamla")
            .disabled(row.isClosed || completed || isBusy || !store.canAddEvent)
            VStack(alignment: .leading, spacing: 4) {
                LinkedTextView(text: row.text, store: store)
                HStack(spacing: 8) {
                    if let date = row.due {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(isOverdue ? Color.red.opacity(0.8) : Color.secondary)
                    }
                    if let priority = row.priority { Text(verbatim: priority.token) }
                }
                .font(.caption)
                if let error = errorText { Text(verbatim: error).font(.caption).foregroundStyle(.red) }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .opacity(completed || row.isClosed ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: completed)
        .onTapGesture {
            if !row.text.spans.contains(where: { $0.target != nil }) { complete() }
        }
        .contextMenu {
            if isToday {
                Button("Metni düzenle", systemImage: "pencil") { textEditor = TaskEditorModel(store: store, row: row) }
                Button("Tarih ver / değiştir", systemImage: "calendar") {
                    dateEditor = TaskEditorModel(store: store, row: row)
                }
                if row.due != nil { Button("Tarihi kaldır") { edit { await $0.setDue(nil) } } }
                Menu("Öncelik") {
                    Button("Yüksek") { edit { await $0.setPriority(.high) } }
                    Button("Orta") { edit { await $0.setPriority(.medium) } }
                    Button("Düşük") { edit { await $0.setPriority(.low) } }
                    Button("Önceliği kaldır") { edit { await $0.setPriority(nil) } }
                }
                Button("Sil", systemImage: "trash", role: .destructive) { edit { await $0.delete() } }
            }
        }
        .sheet(item: $textEditor) { model in
            NavigationStack { TaskTextEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $dateEditor) { model in
            NavigationStack { TaskDateEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .presentationDetents([.medium, .large])
        }
    }

    private func edit(_ operation: @escaping (TaskEditorModel) async -> Bool) {
        Task {
            let model = TaskEditorModel(store: store, row: row)
            await model.load()
            if model.target != nil { _ = await operation(model) }
            errorText = model.errorText
        }
    }
}
