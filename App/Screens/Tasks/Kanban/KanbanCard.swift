import SwiftUI

struct KanbanCard: View {
    let model: KanbanModel
    let row: TaskRow
    let select: () -> Void
    @State private var dateEditor: TaskEditorModel?

    var body: some View {
        card
            .contextMenu {
                Button("Ayrıntıları göster", systemImage: "info.circle", action: select)
                if model.grouping != .person {
                    Menu("Taşı") {
                        ForEach(model.columns) { column in
                            Button {
                                Task { await model.move(row, to: column) }
                            } label: {
                                column.title
                            }
                            .disabled(!model.canMove(row, to: column))
                        }
                    }
                }
                Button("Tarih ver / değiştir", systemImage: "calendar") {
                    dateEditor = TaskEditorModel(store: model.store, row: row)
                }.disabled(!model.store.canAddEvent || model.busy.contains(row.id))
            }
            .sheet(item: $dateEditor) { editor in
                NavigationStack { TaskDateEditor(model: editor) }
                    .frame(minWidth: 320, minHeight: 200).presentationDetents([.medium, .large])
            }
    }

    @ViewBuilder private var card: some View {
        #if os(macOS)
            if model.grouping != .person && model.store.canAddEvent && !model.busy.contains(row.id) {
                buttonContent.onDrag { NSItemProvider(object: model.beginDrag(row) as NSString) }
            } else {
                buttonContent
            }
        #else
            buttonContent
        #endif
    }

    private var presentation: TaskStatusPresentation {
        .make(due: row.due, asOf: model.tasks.day, isCompleted: row.isClosed)
    }

    private var buttonContent: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                LinkedTextView(text: row.text, store: model.store)
                HStack {
                    if let date = row.due {
                        TaskDueDateLabel(date: date, presentation: presentation, includeCalendarIcon: true)
                    }
                    if let priority = row.priority { TaskPriorityMark(priority: priority) }
                    if model.busy.contains(row.id) { ProgressView().controlSize(.small) }
                }.font(.caption)
                if let recurrence = row.recurrence {
                    TaskRecurrenceLabel(recurrence: recurrence).font(.caption).foregroundStyle(.secondary)
                } else if row.recurrenceSource != nil {
                    Label("Tanınmayan tekrar", systemImage: "repeat").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.quaternary) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Ayrıntıları göster"), select)
        .accessibilityAction(named: Text(verbatim: VoiceOverCopy.changeDateActionName())) {
            guard model.store.canAddEvent, !model.busy.contains(row.id) else { return }
            dateEditor = TaskEditorModel(store: model.store, row: row)
        }
        .modifier(KanbanMoveAccessibilityActions(model: model, row: row))
    }
}

/// Chains one VoiceOver action per movable destination column.
private struct KanbanMoveAccessibilityActions: ViewModifier {
    let model: KanbanModel
    let row: TaskRow

    func body(content: Content) -> some View {
        let destinations = model.columns.filter { model.canMove(row, to: $0) }
        return destinations.reduce(AnyView(content)) { view, column in
            AnyView(
                view.accessibilityAction(
                    named: Text(verbatim: VoiceOverCopy.moveActionName(columnTitle: column.localizedTitle))
                ) {
                    Task { await model.move(row, to: column) }
                })
        }
    }
}
