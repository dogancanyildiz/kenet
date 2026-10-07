import SwiftUI

#if os(macOS)
    import ObjectiveC
#endif

struct KanbanCard: View {
    let model: KanbanModel
    let row: TaskRow
    let select: () -> Void
    @State private var dateEditor: TaskEditorModel?
    @Environment(\.locale) private var locale

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
                buttonContent.onDrag { makeDragProvider() }
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

    private var boxState: TaskBoxState {
        TaskBoxState(status: KanbanModel.status(of: row), priority: row.priority)
    }

    private var spokenValue: String {
        var parts: [String] = []
        if let priority = row.priority {
            parts.append(VoiceOverCopy.priorityValue(priority))
        }
        if presentation.showsOverdueCue {
            parts.append(String(localized: "Devreden", locale: locale))
        }
        return parts.joined(separator: ", ")
    }

    private var buttonContent: some View {
        Button(action: select) {
            InkKanbanCard(isDragging: model.draggingRowID == row.id) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        TaskBox(state: boxState, isDecorative: true)
                        LinkedTextView(
                            text: row.text, store: model.store,
                            isMuted: presentation.usesSecondaryText
                        )
                        .font(.ink.content)
                        .foregroundStyle(
                            presentation.usesSecondaryText
                                ? Color.ink.secondaryText : Color.ink.text)
                    }
                    HStack(spacing: 8) {
                        if let date = row.due {
                            TaskDueDateLabel(
                                date: date, presentation: presentation, asOf: model.tasks.day,
                                includeCalendarIcon: true)
                        }
                        if row.priority == .low {
                            TaskPriorityMark(priority: .low)
                        }
                        if model.busy.contains(row.id) { ProgressView().controlSize(.small) }
                    }
                    .font(.ink.meta)
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
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(verbatim: spokenValue))
        .accessibilityAction(named: Text("Ayrıntıları göster"), select)
        .accessibilityAction(named: Text(verbatim: VoiceOverCopy.changeDateActionName())) {
            guard model.store.canAddEvent, !model.busy.contains(row.id) else { return }
            dateEditor = TaskEditorModel(store: model.store, row: row)
        }
        .modifier(KanbanMoveAccessibilityActions(model: model, row: row))
    }

    #if os(macOS)
        private func makeDragProvider() -> NSItemProvider {
            let token = model.beginDrag(row)
            let provider = NSItemProvider(object: token as NSString)
            let endBox = KanbanDragSessionEndBox { [model] in
                Task { @MainActor in model.abandonDrag(token) }
            }
            objc_setAssociatedObject(
                provider, &KanbanDragSessionEndBox.associatedKey, endBox,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return provider
        }
    #endif
}

#if os(macOS)
    /// Retained on the ``NSItemProvider``; `deinit` runs when the drag session ends (drop or cancel).
    private final class KanbanDragSessionEndBox: @unchecked Sendable {
        nonisolated(unsafe) static var associatedKey: UInt8 = 0
        private let onEnd: () -> Void
        init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }
        deinit { onEnd() }
    }
#endif

/// Chains one VoiceOver action per movable destination column.
private struct KanbanMoveAccessibilityActions: ViewModifier {
    let model: KanbanModel
    let row: TaskRow
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        let destinations = model.columns.filter { model.canMove(row, to: $0) }
        return destinations.reduce(AnyView(content)) { view, column in
            AnyView(
                view.accessibilityAction(
                    named: Text(
                        verbatim: VoiceOverCopy.moveActionName(
                            columnTitle: column.localizedTitle(locale: locale)))
                ) {
                    Task { await model.move(row, to: column) }
                })
        }
    }
}
