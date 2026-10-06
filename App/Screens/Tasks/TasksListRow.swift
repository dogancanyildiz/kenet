import SwiftUI
import VaultFormat

/// Interactive task row built from Mürekkep primitives (``TaskBox`` + ``MarginRow`` + linked text).
/// Keeps DayTaskView menus and editors; visual language matches ``InkTaskRow``.
struct TasksListRow: View {
    let store: IndexStore
    let row: TaskRow
    let day: CalendarDate
    let isOverdue: Bool
    let completed: Bool
    let isBusy: Bool
    var allowsReopening = false
    var footnote: Text? = nil
    let complete: () -> Void

    @State private var textEditor: TaskEditorModel?
    @State private var recurrenceEditor: TaskEditorModel?
    @State private var dateEditor: TaskEditorModel?
    @State private var errorText: String?
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    private var presentation: TaskStatusPresentation {
        .make(isPastDue: isOverdue, isCompleted: completed || row.isClosed)
    }

    private var isCompletedCue: Bool { completed || row.isClosed }

    private var boxState: TaskBoxState {
        TaskBoxState(
            status: isCompletedCue ? .done : KanbanModel.status(of: row),
            priority: row.priority)
    }

    private var completion: TasksListRowCompletion {
        .resolve(
            isClosed: row.isClosed,
            completed: completed,
            allowsReopening: allowsReopening,
            isBusy: isBusy,
            canAddEvent: store.canAddEvent)
    }

    var body: some View {
        MarginRow(kind: .vault) {
            TaskBox(
                state: boxState,
                action: completion.canToggleCompletion ? complete : nil,
                accessibilityLabel: LocalizedStringKey(completion.boxAccessibilityLabelKey))
        } primary: {
            LinkedTextView(text: row.text, store: store)
                .foregroundStyle(
                    presentation.usesSecondaryText
                        ? Color.ink.secondaryText
                        : Color.ink.text
                )
                .strikethrough(false)
        } secondary: {
            metaRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if completion.canToggleCompletion, !row.text.spans.contains(where: { $0.target != nil }) {
                complete()
            }
        }
        .accessibilityAction(named: Text(LocalizedStringKey(completion.boxAccessibilityLabelKey))) {
            if completion.canToggleCompletion, !row.text.spans.contains(where: { $0.target != nil }) {
                complete()
            }
        }
        .contextMenu { editMenu }
        .destructiveConfirmationDialog("Görevi sil?", confirmation: $deleteConfirmation) { _ in
            edit { await $0.delete() }
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

    @ViewBuilder private var metaRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let date = row.due {
                    TaskDueDateLabel(date: date, presentation: presentation, asOf: day)
                }
                if row.priority == .low {
                    TaskPriorityMark(priority: .low)
                }
                if let recurrence = row.recurrence {
                    TaskRecurrenceLabel(recurrence: recurrence)
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                } else if row.recurrenceSource != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                        Text("Tanınmayan tekrar")
                    }
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                }
                if isBusy { ProgressView().controlSize(.small) }
            }
            if let footnote {
                footnote
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
            if let error = errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.danger)
            }
        }
    }

    @ViewBuilder private var editMenu: some View {
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
        Button("Sil", systemImage: "trash", role: .destructive) {
            deleteConfirmation.request(.pending)
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
