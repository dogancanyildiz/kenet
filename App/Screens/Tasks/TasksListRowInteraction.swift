import Foundation

/// Where a pointer hit the task row.
enum TasksListRowHit: Equatable, Sendable {
    case box
    case link
    case row
}

/// What that hit does. The box, a link, and the row stay separate controls.
enum TasksListRowClick: Equatable, Sendable {
    case toggleCompletion
    case openLink
    case selectRow
}

/// Mac list column: the box completes, a link opens, the row selects.
/// iPhone: the box completes; a row without a link completes; a link opens and the row does not.
enum TasksListRowInteraction {
    static func action(for hit: TasksListRowHit, hasLink: Bool, isMac: Bool) -> TasksListRowClick? {
        switch hit {
        case .box:
            return .toggleCompletion
        case .link:
            return .openLink
        case .row:
            if isMac { return .selectRow }
            return hasLink ? nil : .toggleCompletion
        }
    }
}
