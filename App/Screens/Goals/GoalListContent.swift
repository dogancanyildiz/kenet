import GoalTracking
import SwiftUI
import VaultFormat

struct GoalListContent: View {
    let store: IndexStore
    let selection: Binding<String?>?
    @Binding var showsCreation: Bool
    @Binding var loaded: GoalListStatuses?
    @Binding var editingGoal: GoalDefinitionSheetTarget?
    /// iPhone: the goal page opened with its amount focused (pencil, "Miktar gir").
    @State private var amountRoute: GoalDetailRoute?
    @State private var deletion = DefinitionDeletionModel()
    @State private var deletingGoal: GoalDefinition?
    @State private var model: GoalDayModel
    /// The request the status answer on screen was asked for (``PageReadyKey``).
    @State private var answeredRequest: GoalListRequest?
    @Environment(\.locale) private var locale

    init(
        store: IndexStore, day: CalendarDate, selection: Binding<String?>?,
        showsCreation: Binding<Bool>, loaded: Binding<GoalListStatuses?>,
        editingGoal: Binding<GoalDefinitionSheetTarget?>
    ) {
        self.store = store
        self.selection = selection
        _showsCreation = showsCreation
        _loaded = loaded
        _editingGoal = editingGoal
        _model = State(initialValue: GoalDayModel(store: store, day: day))
    }

    private var answer: GoalListStatuses? {
        guard let loaded, loaded.vault == store.vaultURL else { return nil }
        return loaded
    }

    private var orderedGoals: [GoalDefinition] {
        guard let answer else { return [] }
        return GoalListPresentation.ordered(answer.goals) { goal in
            model.shownStatus(for: goal, answer: answer.statuses[goal.id])
        }
    }

    /// The summary card's rings: daily and weekly goals (the drawing's Kitap, Su and Spor).
    private var ringGoals: [GoalDefinition] {
        orderedGoals.filter { $0.period != .year && $0.kind != .milestone }
    }

    /// "Bugün 1/3 tamam" under the title: today's goals done out of all ringed goals.
    private var todayLine: String? {
        guard let answer, !ringGoals.isEmpty else { return nil }
        let done = ringGoals.filter {
            model.shownStatus(for: $0, answer: answer.statuses[$0.id]).progress.isComplete
        }.count
        return PresentationLocalization.string(localized: "Bugün \(done)/\(ringGoals.count) tamam", locale: locale)
    }

    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow("Hedefler", byline: todayLine) {
            InkHeaderAction("Yeni hedef", systemImage: "plus") {
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
                // The split shell's column (Mac and iPad drawing) is a compact list: no summary
                // card and no section title, one card per goal.
                if !isColumn, !ringGoals.isEmpty {
                    summaryCard(answer: answer)
                        .inkListRow()
                }
                if !isColumn, !orderedGoals.isEmpty {
                    SectionHeader("Tüm hedefler", count: orderedGoals.count)
                        .padding(.top, 8)
                        .inkListRow()
                }
                ForEach(orderedGoals, id: \.id) { goal in
                    let status = model.shownStatus(for: goal, answer: answer.statuses[goal.id])
                    row(goal: goal, status: status)
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
        .inkGlow()
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
            confirmTitle: "Hedefi sil",
            message: "\(deletingGoal?.name ?? "") silinsin mi? Gün kayıtları kalır."
        ) { path in
            Task {
                if await deletion.delete(store: store, path: path, goal: true),
                    selection?.wrappedValue == path
                {
                    selection?.wrappedValue = nil
                }
            }
        }
        .navigationDestination(item: $amountRoute) { route in
            GoalDetailView(store: store, goal: route.goal, day: model.day, focusesAmount: true)
        }
        .task(id: store.lastUpdated) { await model.load() }
        .task(id: GoalListRequest(day: model.day, updated: store.lastUpdated)) {
            let request = GoalListRequest(day: model.day, updated: store.lastUpdated)
            let vault = store.vaultURL
            let revision = model.currentRevision()
            guard let rows = try? await store.computeGoalStatuses(today: model.day), !Task.isCancelled
            else { return }
            let statuses = rows.map { ($0.definition.id, $0.status) }
            loaded = GoalListStatuses(
                vault: vault, goals: rows.map(\.definition),
                statuses: Dictionary(statuses, uniquingKeysWith: { first, _ in first }))
            if vault == store.vaultURL { model.answerShown(askedAt: revision) }
            answeredRequest = request
        }
        // The rows draw from the status answer, their tallies and marks from the model's history.
        .pageReady(
            answer != nil && answeredRequest == GoalListRequest(day: model.day, updated: store.lastUpdated)
                && model.isCurrent
        )
    }

    /// The split shell passes a selection: the list is its middle column.
    private var isColumn: Bool { selection != nil }

    @ViewBuilder
    private func card(goal: GoalDefinition, status: GoalStatus, markedToday: Bool, markReadOnly: Bool) -> some View {
        if isColumn, let open = openAction(goal: goal, status: status) {
            GoalColumnRow(
                goal: goal, status: status, day: model.day, logs: model.logs[goal.key] ?? [],
                locale: locale, isDisabled: goal.kind == .milestone && (!model.canEdit || markReadOnly),
                markedToday: markedToday,
                isSelected: selection?.wrappedValue == goal.id, onOpen: open)
        } else {
            listCard(goal: goal, status: status, markedToday: markedToday, markReadOnly: markReadOnly)
        }
    }

    @ViewBuilder
    private func row(goal: GoalDefinition, status: GoalStatus) -> some View {
        let markedToday = model.isMarkedToday(goal)
        let markReadOnly =
            goal.kind == .milestone
            && status.completionDate != nil
            && status.completionDate != model.day
        card(goal: goal, status: status, markedToday: markedToday, markReadOnly: markReadOnly)
            .contextMenu {
                // A read-only mark (yesterday already completed) hides only the mark items;
                // Düzenle and Sil stay available.
                DefinitionMenuButtons(
                    items: DefinitionMenu.items(forGoal: goal.kind, markedToday: markedToday)
                        .filter { !markReadOnly || ($0 != .markToday && $0 != .unmark) },
                    canEdit: model.canEdit
                ) { item in
                    switch item {
                    case .markToday, .unmark:
                        Task { await model.toggle(goal) }
                    case .enterAmount:
                        enterAmount(goal)
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
            // The column's card draws its own selection (``View/inkCardSelection(_:cornerRadius:)``).
            .inkListRow(columnSelected: isColumn ? false : selection?.wrappedValue == goal.id)
    }

    private func listCard(
        goal: GoalDefinition, status: GoalStatus, markedToday: Bool, markReadOnly: Bool
    ) -> some View {
        GoalListCard(
            goal: goal,
            status: status,
            day: model.day,
            logs: model.logs[goal.key] ?? [],
            canEdit: model.canEdit,
            markedToday: markedToday,
            markReadOnly: markReadOnly,
            locale: locale,
            onOpen: openAction(goal: goal, status: status),
            opensDetail: goal.kind != .milestone && selection == nil,
            detail: { GoalDetailView(store: store, goal: goal, day: model.day) },
            onIncrement: { Task { await incrementOrToggle(goal) } },
            onEnterAmount: { enterAmount(goal) },
            onUnmark: { Task { await model.toggle(goal) } }
        )
    }

    /// Milestone first (mark), then Mac selection, else nil so the card uses ``NavigationLink``.
    private func openAction(goal: GoalDefinition, status: GoalStatus) -> (() -> Void)? {
        if goal.kind == .milestone {
            let readOnly =
                status.completionDate != nil && status.completionDate != model.day
            return {
                guard !readOnly else { return }
                Task { await model.toggle(goal) }
            }
        }
        if let selection {
            return { selection.wrappedValue = goal.id }
        }
        return nil
    }

    /// The summary card: one large ring per daily and weekly goal, side by side.
    private func summaryCard(answer: GoalListStatuses) -> some View {
        InkCard(padded: true) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(ringGoals, id: \.id) { goal in
                        summaryRing(goal: goal, answer: answer)
                            .frame(maxWidth: .infinity)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(ringGoals, id: \.id) { goal in
                            summaryRing(goal: goal, answer: answer)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summaryRing(goal: GoalDefinition, answer: GoalListStatuses) -> some View {
        let status = model.shownStatus(for: goal, answer: answer.statuses[goal.id])
        let ring = GoalSummaryRingLabel(goal: goal, status: status, locale: locale)
        if let selection {
            Button {
                selection.wrappedValue = goal.id
            } label: {
                ring
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                GoalDetailView(store: store, goal: goal, day: model.day)
            } label: {
                ring
            }
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
        }
    }

    /// The goal page with the amount field focused: pushed on iPhone, selected in the split shell.
    private func enterAmount(_ goal: GoalDefinition) {
        if let selection {
            selection.wrappedValue = goal.id
        } else {
            amountRoute = GoalDetailRoute(goal: goal, focusesAmount: true)
        }
    }

    private func incrementOrToggle(_ goal: GoalDefinition) async {
        if goal.kind == .boolean || goal.kind == .milestone {
            _ = await model.toggle(goal)
        } else {
            let current: Double =
                if case .number(let number) = model.value(for: goal) { number } else { 0 }
            _ = await model.set(goal, value: .number(current + 1))
        }
    }
}
