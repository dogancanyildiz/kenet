import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers
import VaultFormat

struct KanbanCard: View {
    let model: KanbanModel
    let row: TaskRow
    let select: () -> Void
    @State private var dateEditor: TaskEditorModel?
    @Environment(\.locale) private var locale
    @Environment(\.shellKind) private var shellKind

    var body: some View {
        card
            .contextMenu {
                Button("Ayrıntıları göster", systemImage: "info.circle", action: select)
                if model.grouping != .person {
                    Menu("Taşı") {
                        ForEach(model.moveTargets) { target in
                            Button {
                                Task { await model.move(row, to: target) }
                            } label: {
                                target.title
                            }
                            .disabled(!model.canMove(row, to: target))
                        }
                    }
                }
                Button("Tarih ver / değiştir", systemImage: "calendar") {
                    dateEditor = TaskEditorModel(store: model.store, row: row)
                }.disabled(!model.store.canAddEvent || model.busy.contains(row.id))
            }
            .sheet(item: $dateEditor) { editor in
                NavigationStack { TaskDateEditor(model: editor) }
                    .frame(minWidth: 320, minHeight: 200).inkAdaptiveSheetPresentation(fitsContent: true)
            }
    }

    /// Mac and the split iOS shell drag a card to another column (``KanbanBoardStyle/dragsCards``).
    /// On touch the system starts the drag with a long press, after the card's menu lifts, so a
    /// swipe across the board still scrolls it.
    @ViewBuilder private var card: some View {
        if KanbanBoardStyle.resolve(shell: shellKind).dragsCards && model.grouping != .person
            && model.store.canAddEvent && !model.busy.contains(row.id)
        {
            buttonContent.onDrag { makeDragProvider() }
        } else {
            buttonContent
        }
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
                        if let project = row.project {
                            KanbanProjectChip(project: project)
                        }
                        if let date = row.due {
                            if presentation.showsOverdueCue {
                                KanbanCarriedLabel(date: date, today: model.tasks.day)
                            } else {
                                TaskDueDateLabel(
                                    date: date, presentation: presentation, asOf: model.tasks.day,
                                    includeCalendarIcon: true)
                            }
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
            .overlay {
                // Project bar inside the card's corner; the chip carries the project name.
                ProjectColor.color(for: row.project)
                    .frame(width: InkSize.timelineBar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .inkPointerLift()
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

    private func makeDragProvider() -> NSItemProvider {
        let token = model.beginDrag(row)
        let provider = KanbanDragPayload.provider(token: token)
        let endBox = KanbanDragSessionEndBox { [model] in
            Task { @MainActor in model.abandonDrag(token) }
        }
        objc_setAssociatedObject(
            provider, &KanbanDragSessionEndBox.associatedKey, endBox,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return provider
    }
}

/// A carried-over card's short label (Şafak drawing): "↪ 14 Eyl'den" in amber semibold. The
/// arrow and the ablative say "carried over" without the color; VoiceOver reads "Devreden".
struct KanbanCarriedLabel: View {
    let date: CalendarDate
    let today: CalendarDate
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.uturn.right")
                .accessibilityHidden(true)
            Text(verbatim: TodayPresentation.carriedOverDate(date, today: today, locale: locale, calendar: calendar))
        }
        .font(.ink.meta.weight(.semibold))
        .foregroundStyle(.ink.warning)
        .lineLimit(1)
        .overdueAccessibilityValue(true)
    }
}

/// The card's project: a filled capsule with the project's color dot and its name.
struct KanbanProjectChip: View {
    let project: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ProjectColor.color(for: project))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(verbatim: project)
                .font(.ink.meta)
                .foregroundStyle(.ink.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.ink.well))
        .accessibilityElement(children: .combine)
    }
}

/// What a dragged card carries: the board's token (``KanbanModel/beginDrag(_:)``) as plain text,
/// the type the columns' `dropDestination(for: String.self)` reads. On iPad only this app sees
/// it: a card dropped on another app (a note, a message) pastes nothing, not the token. The Mac
/// keeps the provider its drags were verified with.
enum KanbanDragPayload {
    static func provider(token: String) -> NSItemProvider {
        #if os(macOS)
            NSItemProvider(object: token as NSString)
        #else
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .ownProcess
            ) { load in
                load(Data(token.utf8), nil)
                return nil
            }
            return provider
        #endif
    }
}

/// Retained on the ``NSItemProvider``; `deinit` runs when the drag session ends (drop or cancel).
private final class KanbanDragSessionEndBox: @unchecked Sendable {
    nonisolated(unsafe) static var associatedKey: UInt8 = 0
    private let onEnd: () -> Void
    init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }
    deinit { onEnd() }
}

/// Chains one VoiceOver action per movable destination column (``KanbanModel/moveTargets``:
/// the cached column list without rows).
private struct KanbanMoveAccessibilityActions: ViewModifier {
    let model: KanbanModel
    let row: TaskRow
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        let destinations = model.moveTargets.filter { model.canMove(row, to: $0) }
        return destinations.reduce(AnyView(content)) { view, target in
            AnyView(
                view.accessibilityAction(
                    named: Text(
                        verbatim: VoiceOverCopy.moveActionName(
                            columnTitle: target.localizedTitle(locale: locale)))
                ) {
                    Task { await model.move(row, to: target) }
                })
        }
    }
}
