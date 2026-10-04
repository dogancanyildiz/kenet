import VaultFormat
import VaultIndex

@MainActor
struct ProjectModel {
    let store: IndexStore
    let name: String
    var tasks: [TaskRow] {
        store.content.tasks.filter { $0.project.map(VaultIndex.projectKey) == VaultIndex.projectKey(name) }
    }
    var openCount: Int { tasks.filter { !$0.isClosed }.count }
    var openGroups: [TaskAgendaGroup] {
        let groups = Dictionary(grouping: tasks.filter { !$0.isClosed }, by: \.due)
        return groups.keys.sorted {
            guard let left = $0 else { return false }
            guard let right = $1 else { return true }
            return left < right
        }.map { TaskAgendaGroup(date: $0, rows: groups[$0]!.sorted { $0.id < $1.id }) }
    }
    var completed: [TaskRow] {
        tasks.filter { $0.rawStatus == "x" || $0.rawStatus == "X" }.sorted {
            if $0.done != $1.done { return ($0.done?.description ?? "") > ($1.done?.description ?? "") }
            return $0.id < $1.id
        }
    }
    var entities: [EntitySummary] {
        let files = Set(tasks.flatMap(\.linkedFiles))
        return store.content.entities.filter { files.contains($0.id) && ["person", "place"].contains($0.kind) }
            .sorted { $0.id < $1.id }
    }
    var lastActivity: CalendarDate? { tasks.flatMap { [$0.createdDate, $0.done].compactMap { $0 } }.max() }
}
