import Foundation
import Observation
import VaultFormat
import VaultIndex
import VaultStore

struct KanbanColumn: Identifiable {
    enum Destination: Hashable {
        case status(TaskStatus)
        case project(String?)
        case person(String?)
    }
    let id: String
    let destination: Destination
    /// Dynamic names are verbatim; status and unassigned titles are localized by the view.
    let name: String?
    let rows: [TaskRow]
}

@MainActor @Observable
final class KanbanModel {
    enum Grouping: String, CaseIterable { case status, project, person }
    let tasks: TasksModel
    var grouping = Grouping.status
    var showsCancelled = false
    private(set) var busy: Set<String> = []
    private(set) var errorText: String?
    @ObservationIgnored private var drags: [String: (TaskRow, URL?)] = [:]
    var store: IndexStore { tasks.store }

    init(tasks: TasksModel) { self.tasks = tasks }

    private var eligible: [TaskRow] {
        let first = tasks.day.addingDays(-29) ?? tasks.day
        return tasks.filtered.filter { row in
            if row.rawStatus == "-" { return showsCancelled }
            if row.rawStatus == "x" || row.rawStatus == "X" {
                return row.done.map { $0 >= first && $0 <= tasks.day } ?? false
            }
            return true
        }.sorted(by: Self.order)
    }

    var columns: [KanbanColumn] {
        let rows = eligible
        switch grouping {
        case .status:
            let statuses: [TaskStatus] = [.todo, .inProgress, .done] + (showsCancelled ? [.cancelled] : [])
            return statuses.map { status in
                KanbanColumn(
                    id: "status:" + status.rawValue, destination: .status(status), name: nil,
                    rows: rows.filter { Self.status(of: $0) == status })
            }
        case .project:
            return store.content.projects.map { project in
                KanbanColumn(
                    id: "project:" + VaultIndex.projectKey(project), destination: .project(project), name: project,
                    rows: rows.filter { $0.project.map(VaultIndex.projectKey) == VaultIndex.projectKey(project) })
            } + [
                KanbanColumn(
                    id: "project:", destination: .project(nil), name: nil, rows: rows.filter { $0.project == nil })
            ]
        case .person:
            let people = store.content.entities.filter { $0.kind == "person" }
            let paths = Set(people.map(\.id))
            return people.filter { person in rows.contains { $0.linkedFiles.contains(person.id) } }.map { person in
                KanbanColumn(
                    id: "person:" + person.id, destination: .person(person.id),
                    name: person.name + (person.qualifier.map { " (" + $0 + ")" } ?? ""),
                    rows: rows.filter { $0.linkedFiles.contains(person.id) })
            } + [
                KanbanColumn(
                    id: "person:", destination: .person(nil), name: nil,
                    rows: rows.filter { $0.linkedFiles.isDisjoint(with: paths) })
            ]
        }
    }

    nonisolated static func status(of row: TaskRow) -> TaskStatus {
        switch row.rawStatus {
        case "/": .inProgress
        case "x", "X": .done
        case "-": .cancelled
        default: .todo
        }
    }

    nonisolated static func order(_ lhs: TaskRow, _ rhs: TaskRow) -> Bool {
        if lhs.due != rhs.due {
            guard let left = lhs.due else { return false }
            guard let right = rhs.due else { return true }
            return left < right
        }
        if (lhs.priority?.sortRank ?? 2) != (rhs.priority?.sortRank ?? 2) {
            return (lhs.priority?.sortRank ?? 2) < (rhs.priority?.sortRank ?? 2)
        }
        let comparison = lhs.text.plainText.localizedStandardCompare(rhs.text.plainText)
        return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
    }

    func canMove(_ row: TaskRow, to column: KanbanColumn) -> Bool {
        guard grouping != .person, store.canAddEvent, !busy.contains(row.id) else { return false }
        switch column.destination {
        case .status(let status):
            return grouping == .status && Self.status(of: row) != status
        case .project(let project):
            return grouping == .project && row.project.map(VaultIndex.projectKey) != project.map(VaultIndex.projectKey)
        case .person: return false
        }
    }

    @discardableResult
    func move(_ row: TaskRow, to column: KanbanColumn) async -> Bool {
        guard columns.contains(where: { $0.id == column.id && $0.destination == column.destination }),
            canMove(row, to: column)
        else { return false }
        let root = store.vaultURL
        busy.insert(row.id)
        errorText = nil
        defer { busy.remove(row.id) }
        do {
            switch column.destination {
            case .status(let status): try await store.moveTask(row, to: status, on: tasks.day)
            case .project(let project): try await store.moveTask(row, toProject: project)
            case .person: return false
            }
            return true
        } catch VaultStoreError.indexUpdateFailed {
            if root == store.vaultURL { errorText = EntryWriteError.savedWithoutIndex }
            return true
        } catch {
            if root == store.vaultURL { errorText = DayEditError.message(for: error) }
            return false
        }
    }

    /// Only tokens from this board and vault are accepted, retaining the drag-start snapshot.
    func beginDrag(_ row: TaskRow) -> String {
        if drags.count >= 64 { drags.removeAll() }
        let token = UUID().uuidString
        drags[token] = (row, store.vaultURL)
        return token
    }

    func acceptsDrop(_ token: String, into column: KanbanColumn) -> Bool {
        guard let (row, root) = drags[token], root == store.vaultURL else { return false }
        return canMove(row, to: column)
    }

    @discardableResult
    func drop(_ token: String, into column: KanbanColumn) async -> Bool {
        guard let (row, root) = drags.removeValue(forKey: token), root == store.vaultURL else { return false }
        return await move(row, to: column)
    }

    func clearDrags() { drags.removeAll() }
}
