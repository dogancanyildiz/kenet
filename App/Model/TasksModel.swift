import Foundation
import Observation
import VaultFormat
import VaultStore

struct TaskAgendaGroup: Identifiable {
    let date: CalendarDate?
    let rows: [TaskRow]
    var id: String { date?.description ?? "overdue" }
}

@MainActor @Observable
final class TasksModel {
    enum Section: String, CaseIterable { case upcoming, undated, completed }
    let store: IndexStore
    var section = Section.upcoming
    var entityFilter: String?
    var projectFilter: String?
    private(set) var busy: Set<String> = []
    private(set) var errorText: String?
    private let today: () -> CalendarDate

    init(store: IndexStore, today: @escaping () -> CalendarDate = { LocalDay.today() }) {
        self.store = store
        self.today = today
    }

    var day: CalendarDate { today() }
    var projects: [String] { Set(store.content.tasks.compactMap(\.project)).sorted() }
    var hasFilters: Bool { entityFilter != nil || projectFilter != nil }
    func clearFilters() {
        entityFilter = nil
        projectFilter = nil
    }

    private var filtered: [TaskRow] {
        store.content.tasks.filter {
            (entityFilter == nil || $0.linkedFiles.contains(entityFilter!))
                && (projectFilter == nil || $0.project == projectFilter)
        }
    }

    var agenda: [TaskAgendaGroup] {
        let rows = filtered.filter { !$0.isClosed && $0.due != nil }.sorted(by: Self.order)
        let overdue = rows.filter { $0.due! < day }
        let future = Dictionary(grouping: rows.filter { $0.due! >= day }, by: { $0.due! })
        return (overdue.isEmpty ? [] : [TaskAgendaGroup(date: nil, rows: overdue)])
            + future.keys.sorted().map { TaskAgendaGroup(date: $0, rows: future[$0]!) }
    }

    var undated: [TaskRow] { filtered.filter { !$0.isClosed && $0.due == nil }.sorted(by: Self.order) }
    var completed: [TaskRow] {
        Array(
            filtered.filter { $0.rawStatus == "x" || $0.rawStatus == "X" }.sorted {
                if $0.done != $1.done {
                    guard let lhs = $0.done else { return false }
                    guard let rhs = $1.done else { return true }
                    return lhs > rhs
                }
                if $0.file != $1.file { return $0.file < $1.file }
                return $0.sourceLine < $1.sourceLine
            }.prefix(50))
    }

    static func openTasks(in store: IndexStore, linkedTo path: String) -> [TaskRow] {
        store.content.tasks.filter { !$0.isClosed && $0.linkedFiles.contains(path) }.sorted(by: order)
    }

    private static func order(_ lhs: TaskRow, _ rhs: TaskRow) -> Bool {
        if lhs.due != rhs.due {
            guard let left = lhs.due else { return false }
            guard let right = rhs.due else { return true }
            return left < right
        }
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        return lhs.sourceLine < rhs.sourceLine
    }

    @discardableResult
    func toggle(_ row: TaskRow) async -> Bool {
        guard !busy.contains(row.id), store.canAddEvent else { return false }
        let root = store.vaultURL
        busy.insert(row.id)
        errorText = nil
        defer { busy.remove(row.id) }
        do {
            if row.isClosed { try await store.reopenTask(row) } else { try await store.completeTask(row, on: day) }
            return true
        } catch VaultStoreError.indexUpdateFailed {
            if root == store.vaultURL { errorText = EntryWriteError.savedWithoutIndex }
            return true
        } catch {
            if root == store.vaultURL { errorText = DayEditError.message(for: error) }
            return false
        }
    }
}
