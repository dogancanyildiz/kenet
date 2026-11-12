import SwiftUI
import VaultFormat
import VaultStore

/// Task detail (screens.md "Görev ayrıntısı"): task text, label-value card, priority words,
/// recurrence, then "Yarına taşı" / "Haftaya taşı" and the primary "Bitti". A closed task has
/// neither the moves nor "Bitti". The view asks the index for the task again after each write,
/// so a sheet opened with a listed row shows the task as it is now.
struct TaskDetailView: View {
    let store: IndexStore
    let row: TaskRow
    let openDay: (String) -> Void

    @State private var answer = TaskSelectionAnswer()
    @State private var pendingPriority: TaskDetailPriority?
    @State private var recurrenceEditor: TaskEditorModel?
    @State private var errorText: String?
    @State private var isCompleting = false
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow

    /// The task as the index last answered for it; the listed row until then.
    private var task: TaskRow { answer.row(for: row.id, listed: row) ?? row }
    private var today: CalendarDate { LocalDay.today(at: clockNow(), timeZone: calendar.timeZone) }

    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow("Görev") { SearchButton() }
    }

    var body: some View {
        // A table-backed page with the pinned manşet, like every Mac column page
        // (MacPinnedMastheadHostedTests, InkPageScrollColumnTests).
        List {
            InkScrolledMasthead(masthead)
            LinkedTextView(text: task.text, store: store, isMuted: task.isClosed)
                .font(.ink.content)
                .foregroundStyle(task.isClosed ? Color.ink.secondaryText : Color.ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .inkListRow()
            factsCard.inkListRow()
            priorityCard.inkListRow()
            if !task.isClosed {
                actions.inkListRow()
            }
            if let errorText {
                InfoBand(kind: .error, verbatim: errorText).inkListRow()
            }
            if task.createdDate != nil {
                Button("Kaynak güne git") { openDay(task.file) }
                    .buttonStyle(InkTextButtonStyle())
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .inkPinnedMasthead(masthead)
        .inkPageNavigationTitle("Görev")
        .task(id: TaskSelectionRequest(id: row.id, updated: store.lastUpdated)) {
            let request = TaskSelectionRequest(id: row.id, updated: store.lastUpdated)
            if let loaded = await TaskSelectionAnswer.load(request, store: store) { answer = loaded }
        }
        .onChange(of: task.priority) { _, _ in pendingPriority = nil }
        .sheet(item: $recurrenceEditor) { model in
            NavigationStack { TaskRecurrenceEditor(model: model) }
                .inkAdaptiveSheetPresentation(fitsContent: true)
        }
    }

    // MARK: - Label-value card

    private var factsCard: some View {
        let presentation = TaskStatusPresentation.make(due: task.due, asOf: today, isCompleted: task.isClosed)
        let entities = store.content.entities.filter { task.linkedFiles.contains($0.id) }
        return InkCard(padded: false) {
            VStack(spacing: 0) {
                if let project = task.project {
                    field("Proje") { TagChip(title: project, filled: true) }
                    InkCardDivider()
                }
                if let date = task.start {
                    field("Başlangıç tarihi") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                            .font(.ink.value)
                    }
                    InkCardDivider()
                }
                if let date = task.due {
                    field("Bitiş tarihi") {
                        // Carried-over: warning color, arrow and "30 Eyl'den" (TaskDueDateLabel).
                        TaskDueDateLabel(
                            date: date, presentation: presentation, asOf: today,
                            format: .dateTime.day().month().year(), font: .ink.value)
                    }
                    InkCardDivider()
                }
                if let date = task.done {
                    field("Tamamlanma tarihi") {
                        Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                            .font(.ink.value)
                    }
                    InkCardDivider()
                }
                Button {
                    recurrenceEditor = TaskEditorModel(store: store, row: task)
                } label: {
                    field("Tekrar") {
                        HStack(spacing: 6) {
                            recurrenceValue
                            Image(systemName: "chevron.right")
                                .font(.ink.meta)
                                .foregroundStyle(.ink.tertiaryText)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.canAddEvent)
                ForEach(entities) { entity in
                    InkCardDivider()
                    NavigationLink {
                        EntityView(store: store, entity: entity)
                    } label: {
                        EntityRow(entity: entity)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .frame(minHeight: TapTarget.minimumLength)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var recurrenceValue: some View {
        if let recurrence = task.recurrence {
            TaskRecurrenceLabel(recurrence: recurrence)
                .font(.ink.value)
        } else if task.recurrenceSource != nil {
            Text("Tanınmayan tekrar").font(.ink.value)
        } else {
            Text("Yok").font(.ink.value).foregroundStyle(.ink.secondaryText)
        }
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
        .padding(.horizontal, InkSpacing.cardPadding)
        .frame(minHeight: TapTarget.minimumLength)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Priority

    private var priorityCard: some View {
        InkCard {
            Text("Öncelik").font(.ink.meta).foregroundStyle(.ink.secondaryText)
                .accessibilityHidden(true)
            InkTabs(
                selection: prioritySelection,
                items: [
                    InkTabItem("Düşük", value: TaskDetailPriority.low),
                    InkTabItem("Normal", value: TaskDetailPriority.normal),
                    InkTabItem("! Orta", value: TaskDetailPriority.medium),
                    InkTabItem("!! Yüksek", value: TaskDetailPriority.high),
                ],
                accessibilityLabelPrefix: PresentationLocalization.string(
                    localized: "Öncelik", locale: locale)
            )
            .disabled(!store.canAddEvent)
        }
    }

    private var prioritySelection: Binding<TaskDetailPriority> {
        Binding(
            get: { pendingPriority ?? TaskDetailPriority(priority: task.priority) },
            set: { selected in
                // The current word writes nothing: "Normal" on a task with an unknown priority
                // value must not drop that value.
                guard selected != (pendingPriority ?? TaskDetailPriority(priority: task.priority)) else {
                    return
                }
                pendingPriority = selected
                let target = task
                Task {
                    let editor = TaskEditorModel(store: store, row: target)
                    await editor.load()
                    var saved = false
                    if editor.target != nil { saved = await editor.setPriority(selected.priority) }
                    errorText = editor.errorText
                    if !saved { pendingPriority = nil }
                }
            })
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: InkSpacing.row) {
            HStack(spacing: InkSpacing.row) {
                if canMove(to: .tomorrow) {
                    Button("Yarına taşı") { move(to: .tomorrow) }
                        .buttonStyle(InkSecondaryButtonStyle())
                }
                if canMove(to: .nextWeek) {
                    Button("Haftaya taşı") { move(to: .nextWeek) }
                        .buttonStyle(InkSecondaryButtonStyle())
                }
            }
            Button {
                Task { await complete() }
            } label: {
                Text("Bitti").frame(maxWidth: .infinity)
            }
            .buttonStyle(InkPrimaryButtonStyle())
            .disabled(isCompleting || !store.canAddEvent)
        }
    }

    private func move(to destination: TaskMoveDestination) {
        guard let option = moveOptions.first(where: { $0.destination == destination }) else { return }
        let target = task
        Task {
            let editor = TaskEditorModel(store: store, row: target)
            await editor.load()
            if editor.target != nil { _ = await editor.setDue(option.date) }
            errorText = editor.errorText
        }
    }

    private var moveOptions: [TaskMoveOption] {
        TaskMove.options(for: task, on: today, calendar: calendar)
    }

    private func canMove(to destination: TaskMoveDestination) -> Bool {
        store.canAddEvent && moveOptions.contains { $0.destination == destination }
    }

    private func complete() async {
        guard !isCompleting, !task.isClosed else { return }
        isCompleting = true
        defer { isCompleting = false }
        do {
            try await store.completeTask(task, on: today)
            errorText = nil
        } catch VaultStoreError.indexUpdateFailed {
            errorText = EntryWriteError.savedWithoutIndex
        } catch {
            errorText = DayEditError.message(for: error)
        }
    }
}

/// The task detail in a sheet (list and project screens): "Kaynak güne git" opens the day in
/// the sheet's own stack.
private struct TaskDetailSheet: ViewModifier {
    let store: IndexStore
    @Binding var row: TaskRow?
    @State private var sourceDay: CalendarDate?

    func body(content: Content) -> some View {
        content.sheet(item: $row) { row in
            NavigationStack {
                TaskDetailView(store: store, row: row) { path in
                    sourceDay = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                }
                .navigationDestination(item: $sourceDay) { DayView(store: store, date: $0) }
                .inkSheet("Görev", onClose: { self.row = nil })
            }
            .inkAdaptiveSheetPresentation()
        }
    }
}

extension View {
    /// Presents ``TaskDetailView`` for `row` in a sheet.
    func taskDetailSheet(store: IndexStore, row: Binding<TaskRow?>) -> some View {
        modifier(TaskDetailSheet(store: store, row: row))
    }
}

private enum TaskDetailPriority: String, Hashable {
    case low, normal, medium, high

    init(priority: TaskPriority?) {
        switch priority {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        default: self = .normal
        }
    }

    var priority: TaskPriority? {
        switch self {
        case .low: .low
        case .normal: nil
        case .medium: .medium
        case .high: .high
        }
    }
}
