import Foundation
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

extension CloseDayModel {
    /// The flow as Today opens it: with the day's rows the page drew from the index and the
    /// page's goal strip model, loaded.
    static func opened(
        store: IndexStore, today: CalendarDate, step: CloseDayStep = .tasks,
        calendar: Calendar = .autoupdatingCurrent,
        append: (@MainActor (CalendarDate, [String]) async throws -> Void)? = nil
    ) async throws -> CloseDayModel {
        let strip = GoalDayModel(store: store, day: today)
        await strip.load()
        return CloseDayModel(
            store: store, today: today, tasks: try await store.computeDayTasks(on: today), goals: strip, step: step,
            calendar: calendar, append: append)
    }
}

extension ProjectModel {
    /// The project page once its query has answered.
    static func loaded(store: IndexStore, name: String) async throws -> ProjectModel {
        ProjectModel(store: store, name: name, tasks: try await store.computeProjectTasks(name))
    }
}

extension DayTasksModel {
    /// The day's groups once the query has answered.
    static func loaded(store: IndexStore, day: CalendarDate, isToday: Bool) async -> DayTasksModel {
        let model = DayTasksModel(store: store, day: day, isToday: isToday)
        await model.load()
        return model
    }
}

/// The task screens as the app built them before the queries, from the read model's `tasks`
/// (every task row of the vault, file and line order). Kept here as the measure the queries are
/// held to while the field still exists.
@MainActor enum LegacyTaskViews {
    static func filtered(_ rows: [TaskRow], entity: String?, project: String?) -> [TaskRow] {
        rows.filter {
            (entity == nil || $0.linkedFiles.contains(entity!))
                && (project == nil || $0.project.map(VaultIndex.projectKey) == project.map(VaultIndex.projectKey))
        }
    }

    static func agenda(_ rows: [TaskRow], day: CalendarDate) -> [TaskAgendaGroup] {
        let rows = rows.filter { !$0.isClosed && $0.due != nil }.sorted(by: TasksModel.order)
        let overdue = rows.filter { $0.due! < day }
        let future = Dictionary(grouping: rows.filter { $0.due! >= day }, by: { $0.due! })
        return (overdue.isEmpty ? [] : [TaskAgendaGroup(date: nil, rows: overdue)])
            + future.keys.sorted().map { TaskAgendaGroup(date: $0, rows: future[$0]!) }
    }

    static func undated(_ rows: [TaskRow]) -> [TaskRow] {
        rows.filter { !$0.isClosed && $0.due == nil }.sorted(by: TasksModel.order)
    }

    static func completed(_ rows: [TaskRow]) -> [TaskRow] {
        Array(
            rows.filter { $0.rawStatus == "x" || $0.rawStatus == "X" }.sorted {
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
            }.prefix(50))
    }

    static func projectOpenCount(_ rows: [TaskRow], project: String) -> Int {
        rows.filter { $0.project.map(VaultIndex.projectKey) == VaultIndex.projectKey(project) && !$0.isClosed }.count
    }

    /// `KanbanModel.eligible`.
    static func board(_ rows: [TaskRow], day: CalendarDate, showsCancelled: Bool) -> [TaskRow] {
        let first = day.addingDays(-29) ?? day
        return rows.filter { row in
            if row.rawStatus == "-" { return showsCancelled }
            if row.rawStatus == "x" || row.rawStatus == "X" {
                return row.done.map { $0 >= first && $0 <= day } ?? false
            }
            return true
        }.sorted(by: KanbanModel.order)
    }

    /// `TimelineModel.undated`.
    static func timelineUndated(_ rows: [TaskRow]) -> [TaskRow] {
        rows.filter { $0.rawStatus != "-" && $0.start == nil && $0.due == nil }.sorted(by: KanbanModel.order)
    }

    /// `TimelineModel.dated` for one visible window.
    static func timelineDated(_ rows: [TaskRow], today: CalendarDate, window: ClosedRange<CalendarDate>) -> [TaskRow] {
        rows.filter {
            $0.rawStatus != "-" && TimelineDates($0).span(on: today)?.clipped(to: window) != nil
        }.sorted { lhs, rhs in
            let left = lhs.start ?? lhs.due!
            let right = rhs.start ?? rhs.due!
            return left == right ? KanbanModel.order(lhs, rhs) : left < right
        }
    }

    /// `ProjectModel.tasks`.
    static func project(_ rows: [TaskRow], name: String) -> [TaskRow] {
        rows.filter { $0.project.map(VaultIndex.projectKey) == VaultIndex.projectKey(name) }
    }

    /// `CloseDayModel.tasks`.
    static func closeDay(_ rows: [TaskRow], today: CalendarDate) -> [TaskRow] {
        let groups = TaskGroups(rows: rows, on: today, isToday: true)
        return groups.overdue + groups.dated + groups.created
    }
}

extension TaskRow {
    /// Every field a screen draws or a writer finds the task again by, links included.
    var queryKey: String {
        let spans = text.spans.map { "\($0.text)→\($0.destination ?? "")→\($0.target ?? "")" }.joined(separator: "¦")
        return [
            id, file, String(sourceLine), String(sourceEnd), sourceText, sourceIdentifier ?? "", rawStatus,
            due?.description ?? "", start?.description ?? "", done?.description ?? "", priority?.token ?? "",
            project ?? "", recurrenceSource ?? "", linkedFiles.sorted().joined(separator: ","), spans,
        ].joined(separator: "|")
    }
}

extension [TaskRow] {
    var queryKeys: [String] { map(\.queryKey) }
}

extension [TaskAgendaGroup] {
    var queryKeys: [String] { flatMap { group in [group.id] + group.rows.queryKeys } }
}
