import GoalTracking
import SwiftUI
import VaultFormat

/// The goals and statuses the list last queried, statuses by goal file. Kept across the midnight
/// rebuild of the list, so the rows stay until the new day's answer comes; another vault's answer
/// is not used.
struct GoalListStatuses {
    let vault: URL?
    let goals: [GoalDefinition]
    let statuses: [String: GoalStatus]
}

/// Reloads the list's statuses when its day or the published index changes.
struct GoalListRequest: Hashable {
    let day: CalendarDate
    let updated: Date?
}

struct GoalDefinitionSheetTarget: Identifiable {
    let goal: GoalDefinition
    var id: String { goal.id }
}

struct GoalsView: View {
    let store: IndexStore
    var selection: Binding<String?>? = nil
    @State private var showsCreation = false
    @State private var editingGoal: GoalDefinitionSheetTarget?
    @State private var editingAmount: GoalValueModel?
    @State private var loaded: GoalListStatuses?
    @Environment(\.clockNow) private var clockNow
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let day = LocalDay.today(at: clockNow())
            GoalListContent(
                store: store, day: day, selection: selection,
                showsCreation: $showsCreation, loaded: $loaded,
                editingGoal: $editingGoal, editingAmount: $editingAmount
            )
            .id(day.description + (store.vaultURL?.path ?? ""))
        }
        .inkRootPageNavigationTitle("Hedefler")
        .sheet(item: $editingGoal) { goal in
            GoalRowDefinitionEditor(store: store, goal: goal.goal, selection: selection)
        }
        .sheet(item: $editingAmount) { editor in
            NavigationStack { GoalValueEditor(model: editor) }
                .inkAdaptiveSheetPresentation(fitsContent: true, usesPhoneDetents: false)
        }
        .sheet(isPresented: $showsCreation) {
            NavigationStack { GoalCreationView(store: store) }
        }
    }
}

private struct GoalListContent: View {
    let store: IndexStore
    let selection: Binding<String?>?
    @Binding var showsCreation: Bool
    @Binding var loaded: GoalListStatuses?
    @Binding var editingGoal: GoalDefinitionSheetTarget?
    @Binding var editingAmount: GoalValueModel?
    @State private var deletion = DefinitionDeletionModel()
    @State private var deletingGoal: GoalDefinition?
    @State private var model: GoalDayModel
    @Environment(\.locale) private var locale
    init(
        store: IndexStore, day: CalendarDate, selection: Binding<String?>?,
        showsCreation: Binding<Bool>, loaded: Binding<GoalListStatuses?>,
        editingGoal: Binding<GoalDefinitionSheetTarget?>, editingAmount: Binding<GoalValueModel?>
    ) {
        self.store = store
        self.selection = selection
        _showsCreation = showsCreation
        _loaded = loaded
        _editingGoal = editingGoal
        _editingAmount = editingAmount
        _model = State(initialValue: GoalDayModel(store: store, day: day))
    }

    /// The queried goals and statuses of this vault; nil until the first answer, so no row (and no
    /// empty state) is drawn while it is still loading.
    private var answer: GoalListStatuses? {
        guard let loaded, loaded.vault == store.vaultURL else { return nil }
        return loaded
    }

    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow("Hedefler") {
            InkHeaderAction("Yeni hedef", systemImage: "plus", role: .primary) {
                showsCreation = true
            }
            .disabled(!store.canAddEvent)
            SearchButton()
        }
    }

    var body: some View {
        List {
            InkScrolledMasthead(masthead)
            if let answer {
                ForEach(answer.goals, id: \.id) { goal in
                    // A goal marked here and not yet in an answer is drawn from the editing model
                    // until the next.
                    goalRow(goal: goal, status: model.shownStatus(for: goal, answer: answer.statuses[goal.id]))
                }
            }
            if let error = deletion.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .inkPinnedMasthead(masthead)
        .overlay {
            if answer?.goals.isEmpty == true {
                EmptyState(
                    "Henüz hedef yok",
                    actionTitle: store.canAddEvent ? "Yeni hedef" : nil
                ) { showsCreation = true }
            }
        }
        .destructiveConfirmationDialog(
            "Hedefi sil", confirmation: $deletion.confirmation,
            confirmTitle: "Hedefi sil", message: "\(deletingGoal?.name ?? "") silinsin mi? Gün kayıtları kalır."
        ) { path in
            Task {
                if await deletion.delete(store: store, path: path, goal: true), selection?.wrappedValue == path {
                    selection?.wrappedValue = nil
                }
            }
        }
        .task(id: store.lastUpdated) { await model.load() }
        .task(id: GoalListRequest(day: model.day, updated: store.lastUpdated)) {
            let vault = store.vaultURL
            let revision = model.currentRevision()
            guard let rows = try? await store.computeGoalStatuses(today: model.day), !Task.isCancelled else { return }
            let statuses = rows.map { ($0.definition.id, $0.status) }
            loaded = GoalListStatuses(
                vault: vault, goals: rows.map(\.definition),
                statuses: Dictionary(statuses, uniquingKeysWith: { first, _ in first }))
            if vault == store.vaultURL { model.answerShown(askedAt: revision) }
        }
    }

    @ViewBuilder
    private func goalRow(goal: GoalDefinition, status: GoalStatus) -> some View {
        let row = InkGoalRow(
            name: goal.name,
            progress: GoalRowPresentation.progress(goal: goal, status: status),
            // Daily boolean / milestone: empty-or-full mark. Weekly boolean uses a fraction arc.
            isBoolean: goal.kind == .milestone
                || (goal.kind == .boolean && goal.target <= 1),
            meta: GoalRowPresentation.meta(goal: goal, status: status),
            barFraction: GoalRowPresentation.barFraction(goal: goal, status: status),
            valueText: GoalRowPresentation.valueText(goal: goal, status: status),
            graceBadge: GoalRowPresentation.graceBadge(goal: goal, status: status, locale: locale),
            graceBadgePlacement: .streak
        )
        Group {
            if goal.kind == .milestone {
                Button {
                    Task { await model.toggle(goal) }
                } label: {
                    row
                }
                .buttonStyle(.plain)
                .disabled(
                    !model.canEdit
                        || (status.completionDate != nil && status.completionDate != model.day))
            } else if let selection {
                Button {
                    selection.wrappedValue = goal.id
                } label: {
                    // The whole row selects, the empty stretch between name and value included.
                    row.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    GoalDetailView(store: store, goal: goal, day: model.day)
                } label: {
                    row
                }
            }
        }
        .contextMenu {
            DefinitionMenuButtons(
                items: DefinitionMenu.items(forGoal: goal.kind, markedToday: model.isMarkedToday(goal)),
                canEdit: model.canEdit
            ) { item in
                switch item {
                case .markToday, .unmark:
                    Task { await model.toggle(goal) }
                case .enterAmount:
                    editingAmount = GoalValueModel(dayModel: model, goal: goal)
                case .edit:
                    editingGoal = GoalDefinitionSheetTarget(goal: goal)
                case .delete:
                    deletingGoal = goal
                    deletion = DefinitionDeletionModel()
                    deletion.request(path: goal.id)
                case .copyLink: break
                }
            }
        }
        .inkListRow(columnSelected: selection?.wrappedValue == goal.id)
    }
}

/// The form can also delete; clear the split column's selection after that successful write.
private struct GoalRowDefinitionEditor: View {
    let store: IndexStore
    let goal: GoalDefinition
    let selection: Binding<String?>?
    @State private var deletion = DefinitionDeletionModel()

    var body: some View {
        NavigationStack { GoalDefinitionForm(store: store, goal: goal, deletion: deletion) }
            .onChange(of: deletion.isDeleted) { _, deleted in
                if deleted, selection?.wrappedValue == goal.id { selection?.wrappedValue = nil }
            }
    }
}
