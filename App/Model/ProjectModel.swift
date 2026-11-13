import Foundation
import VaultFormat
import VaultIndex

/// Request for a project page's tasks: a write (a new `updated`) asks again.
struct ProjectTasksRequest: Hashable {
    let name: String
    let updated: Date?
}

/// One group under the project page's "Açık görevler" title (drawing: Devreden, Bu hafta,
/// Tarihsiz). "Sonra" holds the tasks due after this week, which the drawing's sample lacks.
struct ProjectOpenSection: Identifiable, Equatable {
    enum Kind: String, Sendable {
        case carriedOver, thisWeek, later, undated

        /// String Catalog key of the group label.
        var catalogKey: String {
            switch self {
            case .carriedOver: "Devreden"
            case .thisWeek: "Bu hafta"
            case .later: "Sonra"
            case .undated: "Tarihsiz"
            }
        }
    }

    let kind: Kind
    let rows: [TaskRow]
    var id: Kind { kind }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.rows.map(\.id) == rhs.rows.map(\.id)
    }
}

@MainActor
struct ProjectModel {
    let store: IndexStore
    let name: String
    /// Every task of the project (``IndexStore/computeProjectTasks(_:)``).
    let tasks: [TaskRow]
    var openCount: Int { tasks.filter { !$0.isClosed }.count }
    var openGroups: [TaskAgendaGroup] {
        let groups = Dictionary(grouping: tasks.filter { !$0.isClosed }, by: \.due)
        return groups.keys.sorted {
            guard let left = $0 else { return false }
            guard let right = $1 else { return true }
            return left < right
        }.map { TaskAgendaGroup(date: $0, rows: groups[$0]!.sorted(by: TasksModel.order)) }
    }
    /// ``openGroups`` gathered around `day`: carried over (the Tasks list's rule, a due day
    /// before `day`), due through the end of the week holding `day` (the week of the Tasks
    /// summary card), due later, undated. Rows keep the order of ``openGroups``; an empty group
    /// is left out.
    func openSections(asOf day: CalendarDate, calendar: Calendar) -> [ProjectOpenSection] {
        let week = TasksWeeklySummary.week(containing: day, calendar: calendar)
        var rows: [ProjectOpenSection.Kind: [TaskRow]] = [:]
        for group in openGroups {
            let kind: ProjectOpenSection.Kind
            if let due = group.date {
                if TaskStatusPresentation.make(due: due, asOf: day, isCompleted: false).showsOverdueCue {
                    kind = .carriedOver
                } else {
                    kind = due <= week.upperBound ? .thisWeek : .later
                }
            } else {
                kind = .undated
            }
            rows[kind, default: []] += group.rows
        }
        return [ProjectOpenSection.Kind.carriedOver, .thisWeek, .later, .undated].compactMap { kind in
            rows[kind].map { ProjectOpenSection(kind: kind, rows: $0) }
        }
    }

    var completed: [TaskRow] {
        tasks.filter { $0.rawStatus == "x" || $0.rawStatus == "X" }.sorted {
            if $0.done != $1.done { return ($0.done?.description ?? "") > ($1.done?.description ?? "") }
            if ($0.priority?.sortRank ?? 2) != ($1.priority?.sortRank ?? 2) {
                return ($0.priority?.sortRank ?? 2) < ($1.priority?.sortRank ?? 2)
            }
            return $0.id < $1.id
        }
    }
    var entities: [EntitySummary] {
        let files = Set(tasks.flatMap(\.linkedFiles))
        return store.content.entities.filter { files.contains($0.id) && ["person", "place"].contains($0.kind) }
            .sorted { $0.id < $1.id }
    }
    var lastActivity: CalendarDate? { tasks.flatMap { [$0.createdDate, $0.done].compactMap { $0 } }.max() }
    /// screens.md: the days the project's tasks were written on, newest first.
    var relatedDays: [CalendarDate] {
        Array(Set(tasks.compactMap(\.createdDate))).sorted(by: >)
    }
}
