import SwiftUI
import VaultFormat
import VaultStore

struct TaskDetailView: View {
    let store: IndexStore
    let row: TaskRow
    let openDay: (String) -> Void

    @State private var recurrenceEditor: TaskEditorModel?
    @State private var errorText: String?
    @State private var isCompleting = false
    @Environment(\.calendar) private var calendar

    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow("Görev") { SearchButton() }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                InkPageHeader("Görev") { SearchButton() }
                    .padding(.horizontal, InkSpacing.margin)
                InkCard {
                    VStack(alignment: .leading, spacing: InkSpacing.row) {
                        HStack(spacing: 8) {
                            if let project = row.project { TagChip(title: project, filled: true) }
                            if let due = row.due {
                                Text(LocalDay.instant(for: due), format: .dateTime.day().month(.abbreviated))
                                    .font(.ink.meta)
                                    .foregroundStyle(due < LocalDay.today() ? Color.ink.warning : Color.ink.secondaryText)
                            }
                        }
                        if let due = row.due, due < LocalDay.today() {
                            Label {
                                Text(LocalDay.instant(for: due), format: .dateTime.day().month(.abbreviated))
                                    .font(.ink.meta)
                            } icon: {
                                Image(systemName: "arrow.forward.circle")
                            }
                            .foregroundStyle(.ink.warning)
                        }
                    }
                }
                .padding(.horizontal, InkSpacing.margin)

                InkCard {
                    VStack(alignment: .leading, spacing: InkSpacing.row) {
                        Text("Öncelik").font(.ink.meta).foregroundStyle(.ink.secondaryText)
                        InkTabs(
                            selection: prioritySelection,
                            items: [
                                InkTabItem("Düşük", value: TaskDetailPriority.low),
                                InkTabItem("Normal", value: TaskDetailPriority.normal),
                                InkTabItem("! Orta", value: TaskDetailPriority.medium),
                                InkTabItem("!! Yüksek", value: TaskDetailPriority.high),
                            ])
                    }
                }
                .padding(.horizontal, InkSpacing.margin)

                InkCard {
                    VStack(alignment: .leading, spacing: InkSpacing.row) {
                        Text("Not").font(.ink.meta).foregroundStyle(.ink.secondaryText)
                        LinkedTextView(text: row.text, store: store)
                            .font(.ink.content).foregroundStyle(.ink.text)
                    }
                }
                .padding(.horizontal, InkSpacing.margin)

                Button {
                    recurrenceEditor = TaskEditorModel(store: store, row: row)
                } label: {
                    InkCard {
                        HStack {
                            Label("Tekrar", systemImage: "repeat")
                                .font(.ink.content).foregroundStyle(.ink.text)
                            Spacer()
                            if let recurrence = row.recurrence {
                                TaskRecurrenceLabel(recurrence: recurrence)
                            } else if row.recurrenceSource != nil {
                                Text("Tanınmayan tekrar")
                                    .font(.ink.meta).foregroundStyle(.ink.secondaryText)
                            } else {
                                Text("Yok").font(.ink.meta).foregroundStyle(.ink.secondaryText)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, InkSpacing.margin)

                HStack(spacing: InkSpacing.row) {
                    Button("Yarına taşı") { move(to: .tomorrow) }
                        .buttonStyle(InkSecondaryButtonStyle())
                        .disabled(!canMove(to: .tomorrow))
                    Button("Haftaya taşı") { move(to: .nextWeek) }
                        .buttonStyle(InkSecondaryButtonStyle())
                        .disabled(!canMove(to: .nextWeek))
                }
                .padding(.horizontal, InkSpacing.margin)

                Button {
                    Task { await complete() }
                } label: {
                    Text(row.isClosed ? "Tamamlandı" : "Bitti")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(InkPrimaryButtonStyle())
                .disabled(row.isClosed || isCompleting || !store.canAddEvent)
                .padding(.horizontal, InkSpacing.margin)

                if let errorText {
                    InfoBand(kind: .error, verbatim: errorText).padding(.horizontal, InkSpacing.margin)
                }
                if row.createdDate != nil {
                    Button("Kaynak güne git") { openDay(row.file) }
                        .buttonStyle(InkTextButtonStyle())
                        .padding(.horizontal, InkSpacing.margin)
                }
            }
            .padding(.vertical, InkSpacing.section)
        }
        .background(Color.ink.elevated)
        .inkPageNavigationTitle("Görev")
        .sheet(item: $recurrenceEditor) { model in
            NavigationStack { TaskRecurrenceEditor(model: model) }
                .inkAdaptiveSheetPresentation(fitsContent: true)
        }
    }

    private var prioritySelection: Binding<TaskDetailPriority> {
        Binding(
            get: { TaskDetailPriority(priority: row.priority) },
            set: { selected in
                Task {
                    let editor = TaskEditorModel(store: store, row: row)
                    await editor.load()
                    if editor.target != nil { _ = await editor.setPriority(selected.priority) }
                    errorText = editor.errorText
                }
            })
    }

    private func move(to destination: TaskMoveDestination) {
        guard let option = moveOptions.first(where: { $0.destination == destination }) else { return }
        Task {
            let editor = TaskEditorModel(store: store, row: row)
            await editor.load()
            if editor.target != nil { _ = await editor.setDue(option.date) }
            errorText = editor.errorText
        }
    }

    private var moveOptions: [TaskMoveOption] {
        TaskMove.options(for: row, on: LocalDay.today(), calendar: calendar)
    }

    private func canMove(to destination: TaskMoveDestination) -> Bool {
        store.canAddEvent && moveOptions.contains { $0.destination == destination }
    }

    private func complete() async {
        guard !isCompleting, !row.isClosed else { return }
        isCompleting = true
        defer { isCompleting = false }
        do {
            try await store.completeTask(row, on: LocalDay.today())
        } catch VaultStoreError.indexUpdateFailed {
            errorText = EntryWriteError.savedWithoutIndex
        } catch {
            errorText = DayEditError.message(for: error)
        }
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
