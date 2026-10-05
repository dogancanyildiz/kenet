import SwiftUI
import VaultFormat

struct DayTaskView: View {
    let store: IndexStore
    let row: TaskRow
    let isToday: Bool
    let isOverdue: Bool
    let completed: Bool
    let isBusy: Bool
    var allowsReopening = false
    let complete: () -> Void
    @State private var textEditor: TaskEditorModel?
    @State private var recurrenceEditor: TaskEditorModel?
    @State private var dateEditor: TaskEditorModel?
    @State private var errorText: String?

    private var presentation: TaskStatusPresentation {
        .make(isPastDue: isOverdue, isCompleted: completed || row.isClosed)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: complete) {
                Image(systemName: completed || row.isClosed ? "checkmark.square.fill" : "square")
            }
            .accessibilityLabel(
                LocalizedStringKey(row.isClosed && allowsReopening ? "Görevi yeniden aç" : "Görevi tamamla")
            )
            .disabled((row.isClosed && !allowsReopening) || completed || isBusy || !store.canAddEvent)
            completedTextStyle {
                VStack(alignment: .leading, spacing: 4) {
                    LinkedTextView(text: row.text, store: store)
                    HStack(spacing: 8) {
                        if let date = row.due {
                            TaskDueDateLabel(date: date, presentation: presentation)
                        }
                        if let priority = row.priority { Text(verbatim: priority.token).accessibilityLabel("Öncelik") }
                        if let recurrence = row.recurrence {
                            TaskRecurrenceLabel(recurrence: recurrence)
                        } else if row.recurrenceSource != nil {
                            Label("Tanınmayan tekrar", systemImage: "repeat")
                        }
                    }
                    .font(.caption)
                    if let error = errorText { Text(verbatim: error).font(.caption).foregroundStyle(.red) }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .opacity(presentation.opacity)
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
                Button("Tekrar", systemImage: "repeat") { recurrenceEditor = TaskEditorModel(store: store, row: row) }
                Menu("Öncelik") {
                    Button("Yüksek") { edit { await $0.setPriority(.high) } }
                    Button("Orta") { edit { await $0.setPriority(.medium) } }
                    Button("Düşük") { edit { await $0.setPriority(.low) } }
                    Button("Yok") { edit { await $0.setPriority(nil) } }
                }
                Button("Sil", systemImage: "trash", role: .destructive) { edit { await $0.delete() } }
            }
        }
        .sheet(item: $textEditor) { model in
            NavigationStack { TaskTextEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $recurrenceEditor) { model in
            NavigationStack { TaskRecurrenceEditor(model: model) }.presentationDetents([.medium, .large])
        }
        .sheet(item: $dateEditor) { model in
            NavigationStack { TaskDateEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private func completedTextStyle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if presentation.usesSecondaryText {
            content().foregroundStyle(.secondary)
        } else {
            content()
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
