import Foundation
import Observation
import VaultFormat
import VaultIndex
import VaultStore

struct TaskAgendaGroup: Identifiable {
    let date: CalendarDate?
    let rows: [TaskRow]
    var id: String { date?.description ?? "overdue" }
}

/// Request for a task list: a new value (a write, a filter, a new day) asks the index again.
struct TaskListRequest: Hashable {
    let scope: TaskScope
    let day: CalendarDate
    let updated: Date?
}

/// Open tasks split around a day, from ``IndexStore/computeTaskGroups(today:scope:)``.
struct TaskRowGroups: Sendable {
    var overdue: [TaskRow] = []
    var today: [TaskRow] = []
    var upcoming: [TaskRow] = []
    var undated: [TaskRow] = []

    init() {}

    init(_ entries: TaskGroupEntries) {
        overdue = entries.overdue.map(TaskRow.init(entry:))
        today = entries.today.map(TaskRow.init(entry:))
        upcoming = entries.upcoming.map(TaskRow.init(entry:))
        undated = entries.undated.map(TaskRow.init(entry:))
    }

    /// Every open task, each group in ``TasksModel/order(_:_:)``.
    var open: [TaskRow] { (overdue + today + upcoming + undated).sorted(by: TasksModel.order) }
}

/// The Tasks list's sections for one request.
struct TaskListContent {
    /// Overdue tasks first ("Devreden"), then one group per due day from today on.
    let agenda: [TaskAgendaGroup]
    let undated: [TaskRow]
    /// Newest completion first.
    let completed: [TaskRow]
    /// Open tasks per project key, whatever the filters.
    let projectOpenCounts: [String: Int]

    init(groups: TaskRowGroups, completed: [TaskRow], projectOpenCounts: [String: Int]) {
        let overdue = groups.overdue.sorted(by: TasksModel.order)
        let future = Dictionary(
            grouping: (groups.today + groups.upcoming).sorted(by: TasksModel.order), by: { $0.due! })
        agenda =
            (overdue.isEmpty ? [] : [TaskAgendaGroup(date: nil, rows: overdue)])
            + future.keys.sorted().map { TaskAgendaGroup(date: $0, rows: future[$0]!) }
        undated = groups.undated.sorted(by: TasksModel.order)
        self.completed = Array(
            completed.sorted {
                if $0.done != $1.done {
                    guard let lhs = $0.done else { return false }
                    guard let rhs = $1.done else { return true }
                    return lhs > rhs
                }
                if ($0.priority?.sortRank ?? 2) != ($1.priority?.sortRank ?? 2) {
                    return ($0.priority?.sortRank ?? 2) < ($1.priority?.sortRank ?? 2)
                }
                if $0.file != $1.file { return $0.file < $1.file }
                return $0.sourceLine < $1.sourceLine
            }.prefix(TasksModel.completedLimit))
        self.projectOpenCounts = projectOpenCounts
    }
}

extension TaskRow {
    init(entry: TaskEntry) { self.init(row: entry.block, links: entry.links) }

    /// The read model's order: file, then line.
    nonisolated static func sourceOrder(_ lhs: TaskRow, _ rhs: TaskRow) -> Bool {
        lhs.file != rhs.file ? lhs.file < rhs.file : lhs.sourceLine < rhs.sourceLine
    }
}

@MainActor @Observable
final class TasksModel {
    /// Six-way value from before the two-layer selector; kept for callers that jump to one
    /// view (sidebar, notification) and for reading the old device preference.
    enum Section: String, CaseIterable { case upcoming, undated, completed, projects, kanban, timeline }
    let store: IndexStore
    /// Tab, list section and each board's last menu choice (``TasksViewState``).
    var viewState = TasksViewState()
    var section: Section {
        get { viewState.legacySection }
        set { viewState.apply(newValue) }
    }
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
    /// Project names (``IndexStore/computeProjects()``), set with each list, board or timeline
    /// answer; a reload keeps the previous names until then.
    var projects: [String] = []
    var hasFilters: Bool { entityFilter != nil || projectFilter != nil }
    func clearFilters() {
        entityFilter = nil
        projectFilter = nil
    }

    /// The filters as the task queries take them.
    var scope: TaskScope { TaskScope(linkedTo: entityFilter, project: projectFilter) }

    /// What the list asks the index for; a write, a filter or a new day asks again.
    var listRequest: TaskListRequest { TaskListRequest(scope: scope, day: day, updated: store.lastUpdated) }

    /// The list's sections, nil until the first answer; a reload keeps the previous ones until then.
    private(set) var list: TaskListContent?
    /// The request `list` answers.
    private(set) var loadedListRequest: TaskListRequest?
    /// Whether `list` answers the current filters, day and publish.
    var isListCurrent: Bool { list != nil && loadedListRequest == listRequest }

    /// Why the latest list read failed; the next answer clears it.
    private(set) var listErrorText: String?

    /// Asks for `listRequest`'s sections. A reload cancelled or outlived by its vault leaves the
    /// list as it was; a failed one leaves it too and sets `listErrorText`.
    func loadList() async {
        let request = listRequest
        let outcome = await QueryOutcome.of {
            (
                try await store.computeTaskGroups(today: request.day, scope: request.scope),
                try await store.computeCompletedTasks(limit: Self.completedLimit, scope: request.scope),
                try await store.computeOpenTaskCounts(),
                try await store.computeProjects()
            )
        }
        switch outcome {
        case .answer(let (groups, completed, counts, names)):
            list = TaskListContent(groups: groups, completed: completed, projectOpenCounts: counts)
            projects = names
            loadedListRequest = request
            listErrorText = nil
        case .cancelled, .stale:
            break
        case .failed:
            listErrorText = outcome.errorText
        }
    }

    var agenda: [TaskAgendaGroup] { list?.agenda ?? [] }
    var undated: [TaskRow] { list?.undated ?? [] }
    var completed: [TaskRow] { list?.completed ?? [] }

    /// Open tasks of `project` (any spelling of its key), whatever the filters.
    func openCount(ofProject project: String) -> Int { list?.projectOpenCounts[VaultIndex.projectKey(project)] ?? 0 }

    /// The listed row with `id`, in any section.
    func listedRow(id: String?) -> TaskRow? {
        guard let id, let list else { return nil }
        return (list.agenda.flatMap(\.rows) + list.undated + list.completed).first { $0.id == id }
    }

    nonisolated static let completedLimit = 50

    nonisolated static func order(_ lhs: TaskRow, _ rhs: TaskRow) -> Bool {
        if lhs.due != rhs.due {
            guard let left = lhs.due else { return false }
            guard let right = rhs.due else { return true }
            return left < right
        }
        if (lhs.priority?.sortRank ?? 2) != (rhs.priority?.sortRank ?? 2) {
            return (lhs.priority?.sortRank ?? 2) < (rhs.priority?.sortRank ?? 2)
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
