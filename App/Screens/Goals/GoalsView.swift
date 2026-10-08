import GoalTracking
import SwiftUI
import VaultFormat

struct GoalsView: View {
    let store: IndexStore
    var selection: Binding<String?>? = nil
    @State private var showsCreation = false
    @Environment(\.clockNow) private var clockNow
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let day = LocalDay.today(at: clockNow())
            GoalListContent(
                store: store, day: day, selection: selection,
                showsCreation: $showsCreation
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
    @State private var model: GoalDayModel
    init(
        store: IndexStore, day: CalendarDate, selection: Binding<String?>?,
        showsCreation: Binding<Bool>
    ) {
        self.store = store
        self.selection = selection
        _showsCreation = showsCreation
        _model = State(initialValue: GoalDayModel(store: store, day: day))
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
            ForEach(store.content.goals, id: \.id) { goal in
                let status =
                    model.hasLoaded
                    ? model.status(for: goal) : (store.content.goalStatuses[goal.key] ?? model.status(for: goal))
                goalRow(goal: goal, status: status)
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageColumn()
        .overlay {
            if store.content.goals.isEmpty {
                EmptyState(
                    "Henüz hedef yok",
                    actionTitle: store.canAddEvent ? "Yeni hedef" : nil
                ) { showsCreation = true }
            }
        }
        .task(id: store.lastUpdated) { await model.load() }
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
                    row
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
