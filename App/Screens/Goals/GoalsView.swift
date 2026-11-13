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
    @State private var loaded: GoalListStatuses?
    @Environment(\.clockNow) private var clockNow
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let day = LocalDay.today(at: clockNow())
            GoalListContent(
                store: store, day: day, selection: selection,
                showsCreation: $showsCreation, loaded: $loaded,
                editingGoal: $editingGoal
            )
            .id(day.description + (store.vaultURL?.path ?? ""))
        }
        .inkRootPageNavigationTitle("Hedefler")
        .sheet(item: $editingGoal) { goal in
            NavigationStack { GoalDefinitionForm(store: store, goal: goal.goal) }
        }
        .sheet(isPresented: $showsCreation) {
            NavigationStack { GoalCreationView(store: store) }
        }
    }
}
