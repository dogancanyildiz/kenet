import SwiftUI
import VaultFormat

/// Interactive task row built from Mürekkep primitives (``TaskBox`` + ``MarginRow`` + linked text).
/// Keeps DayTaskView menus and editors; visual language matches ``InkTaskRow``.
/// Phone tabs: a touch on the row completes a task without links. In the split shell and
/// on Mac the row belongs to list selection, so only the box completes.
struct TasksListRow: View {
    let store: IndexStore
    let row: TaskRow
    let day: CalendarDate
    let isOverdue: Bool
    let isBusy: Bool
    var allowsReopening = false
    var footnote: Text? = nil
    let complete: () -> Void

    @Environment(\.shellKind) private var shellKind
    @State private var textEditor: TaskEditorModel?
    @State private var recurrenceEditor: TaskEditorModel?
    @State private var dateEditor: TaskEditorModel?
    @State private var errorText: String?
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    private var presentation: TaskStatusPresentation {
        .make(isPastDue: isOverdue, isCompleted: row.isClosed)
    }

    private var boxState: TaskBoxState {
        TaskBoxState(
            status: row.isClosed ? .done : KanbanModel.status(of: row),
            priority: row.priority)
    }

    private var completion: TasksListRowCompletion {
        .make(
            from: row,
            allowsReopening: allowsReopening,
            isBusy: isBusy,
            canAddEvent: store.canAddEvent)
    }

    private var rowTapCompletes: Bool {
        TasksListRowTouch.completes(
            canToggle: completion.canToggleCompletion,
            hasLinks: row.text.spans.contains(where: { $0.target != nil }))
    }

    var body: some View {
        MarginRow(kind: .vault) {
            TaskBox(
                state: boxState,
                action: completion.canToggleCompletion ? complete : nil,
                accessibilityLabel: LocalizedStringKey(completion.boxAccessibilityLabelKey))
        } primary: {
            LinkedTextView(
                text: row.text, store: store, isMuted: presentation.usesSecondaryText
            )
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
        #if !os(macOS)
            .contentShape(Rectangle())
            .modifier(TasksListRowTouch.Tap(shell: shellKind, completes: rowTapCompletes, complete: complete))
        #endif
        .accessibilityAction(named: Text(LocalizedStringKey(completion.boxAccessibilityLabelKey))) {
            if rowTapCompletes { complete() }
        }
        .accessibilityActions { moveButtons }
        .contextMenu { editMenu }
        #if os(macOS)
            // The list column draws the selection; the system focus ring would double it.
            .focusEffectDisabled()
        #endif
        .destructiveConfirmationDialog("Görevi sil?", confirmation: $deleteConfirmation) { _ in
            edit { await $0.delete() }
        }
        .sheet(item: $textEditor) { model in
            NavigationStack { TaskTextEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .inkAdaptiveSheetPresentation()
        }
        .sheet(item: $recurrenceEditor) { model in
            NavigationStack { TaskRecurrenceEditor(model: model) }.inkAdaptiveSheetPresentation()
        }
        .sheet(item: $dateEditor) { model in
            NavigationStack { TaskDateEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .inkAdaptiveSheetPresentation()
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
        moveButtons
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

    private var moveButtons: TaskMoveButtons {
        TaskMoveButtons(row: row, today: day) { date in edit { await $0.setDue(date) } }
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

/// What a touch on the row does, by shell (unit-tested).
enum TasksListRowTouch {
    /// Tabs: the row's own tap is live. Split: the row adds no gesture of its own, so the touch
    /// reaches the list's selection; the box and the links (subviews) keep theirs.
    static func gestureMask(in shell: ShellKind) -> GestureMask {
        shell == .tabs ? .all : .subviews
    }

    /// The row's tap completes an enabled task whose text holds no link (a link takes its own touch).
    static func completes(canToggle: Bool, hasLinks: Bool) -> Bool {
        canToggle && !hasLinks
    }

    /// The row's tap with the shell's mask; the gesture is built here, in one place, so a call
    /// site cannot attach it with a mask of its own.
    struct Tap: ViewModifier {
        let shell: ShellKind
        let completes: Bool
        let complete: () -> Void

        func body(content: Content) -> some View {
            content.gesture(
                TapGesture().onEnded { if completes { complete() } },
                including: TasksListRowTouch.gestureMask(in: shell))
        }
    }
}
