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
    /// The section's day (Tarihsiz: created, Tamamlanan: completed) on the meta line in place
    /// of the due date.
    var footnote: Text? = nil
    var openDetail: () -> Void = {}
    /// The Tasks list names a task with no project "Projesiz" on its meta line; the project
    /// page (one project) does not.
    var namesMissingProject = false
    let complete: () -> Void

    @Environment(\.shellKind) private var shellKind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
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

    /// The detail entry (menu and VoiceOver action): the phone's tab shell only. On Mac and in
    /// the split shell a click on the row selects it and the detail column shows it.
    private var showsDetailEntry: Bool {
        #if os(macOS)
            false
        #else
            shellKind == .tabs
        #endif
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
            // One line, cut at the end (the detail shows the whole text); accessibility sizes wrap.
            LinkedTextView(
                text: row.text, store: store, isMuted: presentation.usesSecondaryText
            )
            .foregroundStyle(
                presentation.usesSecondaryText
                    ? Color.ink.secondaryText
                    : Color.ink.text
            )
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .strikethrough(false)
        } secondary: {
            metaRow
        } trailing: {
            detailChevron
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Inside the section card (`inkListRow(cardSegment:)` draws it behind the row). Completed
        // rows fade through secondary text and the filled box, never opacity (design.md).
        .padding(.horizontal, InkSpacing.cardPadding)
        #if !os(macOS)
            .contentShape(Rectangle())
            .modifier(TasksListRowTouch.Tap(shell: shellKind, completes: rowTapCompletes, complete: complete))
        #endif
        .accessibilityAction(named: Text(LocalizedStringKey(completion.boxAccessibilityLabelKey))) {
            if rowTapCompletes { complete() }
        }
        .accessibilityActions {
            if showsDetailEntry {
                Button("Ayrıntıları göster", action: openDetail)
            }
            moveButtons
        }
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
                .inkAdaptiveSheetPresentation(fitsContent: true)
        }
        .sheet(item: $recurrenceEditor) { model in
            NavigationStack { TaskRecurrenceEditor(model: model) }.inkAdaptiveSheetPresentation(fitsContent: true)
        }
        .sheet(item: $dateEditor) { model in
            NavigationStack { TaskDateEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .inkAdaptiveSheetPresentation(fitsContent: true)
        }
    }

    /// The phone's way into the detail beside the row (the row's own touch completes it).
    /// Mac and the split shell select the row instead and draw no chevron.
    @ViewBuilder private var detailChevron: some View {
        if showsDetailEntry {
            Button(action: openDetail) {
                Image(systemName: "chevron.right")
                    .font(.ink.meta.weight(.semibold))
                    .foregroundStyle(.ink.tertiaryText)
                    .tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }

    /// "Projesiz" stands for a missing project on the Tasks list.
    private var projectName: Text? {
        if let project = row.project { return Text(verbatim: project) }
        return namesMissingProject ? Text("Projesiz") : nil
    }

    /// A carried-over task's whole meta line is in the warning color:
    /// "→ mobil · 14 Eyl'den devretti".
    @ViewBuilder private var overdueLine: some View {
        if let date = row.due {
            let carried = TodayPresentation.carriedOverDate(date, today: day, locale: locale, calendar: calendar)
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
                if let projectName {
                    projectName
                    Text(verbatim: "·").accessibilityHidden(true)
                }
                Text("\(carried) devretti")
            }
            .font(.ink.meta)
            .foregroundStyle(.ink.warning)
            .lineLimit(1)
            .overdueAccessibilityValue(true)
        }
    }

    @ViewBuilder private var metaRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if presentation.showsOverdueCue && row.due != nil {
                    overdueLine
                } else {
                    // The section's own day (created, completed) takes the due date's place.
                    let shownDay = footnote != nil || row.due != nil
                    if let projectName {
                        projectName
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                        if shownDay {
                            Text(verbatim: "·")
                                .font(.ink.meta)
                                .foregroundStyle(.ink.tertiaryText)
                                .accessibilityHidden(true)
                        }
                    }
                    if let footnote {
                        footnote
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                    } else if let date = row.due {
                        TaskDueDateLabel(date: date, presentation: presentation, asOf: day)
                    }
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
            if let error = errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.danger)
            }
        }
    }

    @ViewBuilder private var editMenu: some View {
        // The phone's way into the detail sheet: a touch on the row completes the task
        // (screens.md "Tamamlama"), so the detail sits in the menu, not behind a chevron whose
        // touch area would take touches meant for the row.
        if showsDetailEntry {
            Button("Ayrıntıları göster", systemImage: "info.circle", action: openDetail)
        }
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
