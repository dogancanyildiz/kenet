import GoalTracking
import SwiftUI
import VaultFormat

/// Goal statuses the list last queried, by goal file. Kept across the midnight rebuild of the list,
/// so the rows stay until the new day's answer comes; another vault's answer is not used.
struct GoalListStatuses {
    let vault: URL?
    let statuses: [String: GoalStatus]
}

/// Reloads the list's statuses when its day or the published index changes.
struct GoalListRequest: Hashable {
    let day: CalendarDate
    let updated: Date?
}

struct GoalsView: View {
    let store: IndexStore
    var selection: Binding<String?>? = nil
    @State private var showsCreation = false
    @State private var loaded: GoalListStatuses?
    @Environment(\.clockNow) private var clockNow
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let day = LocalDay.today(at: clockNow())
            GoalListContent(
                store: store, day: day, selection: selection,
                showsCreation: $showsCreation, loaded: $loaded
            )
            .id(day.description + (store.vaultURL?.path ?? ""))
        }
        .inkRootPageNavigationTitle("Hedefler")
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
    @State private var model: GoalDayModel
    init(
        store: IndexStore, day: CalendarDate, selection: Binding<String?>?,
        showsCreation: Binding<Bool>, loaded: Binding<GoalListStatuses?>
    ) {
        self.store = store
        self.selection = selection
        _showsCreation = showsCreation
        _loaded = loaded
        _model = State(initialValue: GoalDayModel(store: store, day: day))
    }

    /// The queried statuses of this vault; nil until the first answer, so no row is drawn with a
    /// status still loading.
    private var statuses: [String: GoalStatus]? {
        guard let loaded, loaded.vault == store.vaultURL else { return nil }
        return loaded.statuses
    }

    var body: some View {
        List {
            InkPageTitleRow("Hedefler") {
                InkHeaderAction("Yeni hedef", systemImage: "plus", role: .primary) {
                    showsCreation = true
                }
                .disabled(!store.canAddEvent)
                SearchButton()
            }
            if let statuses {
                ForEach(store.content.goals, id: \.id) { goal in
                    // A goal created since the last answer is drawn from the editing model until the next.
                    goalRow(goal: goal, status: statuses[goal.id] ?? model.status(for: goal))
                }
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .overlay {
            if store.content.goals.isEmpty {
                EmptyState(
                    "Henüz hedef yok",
                    actionTitle: store.canAddEvent ? "Yeni hedef" : nil
                ) { showsCreation = true }
            }
        }
        .task(id: store.lastUpdated) { await model.load() }
        .task(id: GoalListRequest(day: model.day, updated: store.lastUpdated)) {
            let vault = store.vaultURL
            guard let rows = try? await store.computeGoalStatuses(today: model.day), !Task.isCancelled else { return }
            let statuses = rows.map { ($0.definition.id, $0.status) }
            loaded = GoalListStatuses(
                vault: vault, statuses: Dictionary(statuses, uniquingKeysWith: { first, _ in first }))
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
            valueText: GoalRowPresentation.valueText(goal: goal, status: status)
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
        .inkListRow(columnSelected: selection?.wrappedValue == goal.id)
    }
}
