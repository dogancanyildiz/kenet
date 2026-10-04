import GoalTracking
import SwiftUI
import VaultFormat

struct GoalsView: View {
    let store: IndexStore
    var selection: Binding<String?>? = nil
    @State private var showsCreation = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GoalListContent(store: store, day: LocalDay.today(at: context.date), selection: selection)
                .id(LocalDay.today(at: context.date).description + (store.vaultURL?.path ?? ""))
        }
        .navigationTitle("Hedefler")
        .toolbar {
            Button("Yeni hedef", systemImage: "plus") { showsCreation = true }.disabled(!store.canAddEvent)
            SearchButton()
        }
        .sheet(isPresented: $showsCreation) { NavigationStack { GoalCreationView(store: store) } }
    }
}

private struct GoalListContent: View {
    let store: IndexStore
    let selection: Binding<String?>?
    @State private var model: GoalDayModel
    init(store: IndexStore, day: CalendarDate, selection: Binding<String?>?) {
        self.store = store
        self.selection = selection
        _model = State(initialValue: GoalDayModel(store: store, day: day))
    }
    var body: some View {
        List {
            ForEach(store.content.goals, id: \.id) { goal in
                let status =
                    model.hasLoaded
                    ? model.status(for: goal) : (store.content.goalStatuses[goal.key] ?? model.status(for: goal))
                if goal.kind == .milestone {
                    Button {
                        Task { await model.toggle(goal) }
                    } label: {
                        GoalCard(goal: goal, status: status)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canEdit || (status.completionDate != nil && status.completionDate != model.day))
                } else if let selection {
                    Button {
                        selection.wrappedValue = goal.id
                    } label: {
                        GoalCard(goal: goal, status: status)
                    }
                    .buttonStyle(.plain).listRowBackground(
                        selection.wrappedValue == goal.id ? Color.accentColor.opacity(0.12) : Color.clear)
                } else {
                    NavigationLink {
                        GoalDetailView(store: store, goal: goal)
                    } label: {
                        GoalCard(goal: goal, status: status)
                    }
                }
            }
            if let error = model.errorText { Text(verbatim: error).foregroundStyle(.secondary) }
        }
        .overlay {
            if store.content.goals.isEmpty {
                ContentUnavailableView(
                    "Henüz hedef yok", systemImage: "target", description: Text("Yeni hedef ekleyerek başla."))
            }
        }
        .task(id: store.lastUpdated) { await model.load() }
    }
}
