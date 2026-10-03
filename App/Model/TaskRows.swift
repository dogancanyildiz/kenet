import VaultFormat
import VaultIndex

struct TaskRow: Identifiable, Sendable {
    let id: String
    let file: String
    let text: LinkedText
    let sourceLine: Int
    let sourceEnd: Int
    let sourceText: String
    let sourceIdentifier: String?
    let rawStatus: String
    let due: CalendarDate?
    let start: CalendarDate?
    let done: CalendarDate?
    let priority: TaskPriority?
    let project: String?
    let linkedFiles: Set<String>

    var createdDate: CalendarDate? {
        guard file.hasPrefix("journal/"), file.hasSuffix(".md") else { return nil }
        return CalendarDate(String(file.dropFirst(8).dropLast(3)))
    }

    var isClosed: Bool { rawStatus == "x" || rawStatus == "X" || rawStatus == "-" }

    init(row: IndexedBlock, links: [IndexedLink]) {
        file = row.file
        id =
            row.file
            + (row.ownsIdentifier && row.identifier != nil ? "^" + row.identifier! : "#" + String(row.firstLine))
        text = LinkedText(row: row, links: links)
        sourceLine = row.firstLine - 1
        sourceEnd = row.lastLine
        sourceText = row.text
        sourceIdentifier = row.identifier
        rawStatus = row.rawStatus ?? " "
        due = row.dueDate.flatMap { CalendarDate($0) }
        start = row.startDate.flatMap { CalendarDate($0) }
        done = row.doneDate.flatMap { CalendarDate($0) }
        switch row.priority {
        case "⏫": priority = .high
        case "🔼": priority = .medium
        case "🔽": priority = .low
        case .some(let token): priority = .other(token)
        case nil: priority = nil
        }
        project = row.project
        linkedFiles = Set(links.filter { $0.block == row.ordinal }.compactMap(\.resolvedFile))
    }
}

struct TaskGroups {
    var overdue: [TaskRow] = []
    var dated: [TaskRow] = []
    var created: [TaskRow] = []
    var isEmpty: Bool { overdue.isEmpty && dated.isEmpty && created.isEmpty }

    init(rows: [TaskRow], on day: CalendarDate, isToday: Bool) {
        let eligible = rows.filter { !isToday || !$0.isClosed }
        if isToday {
            overdue = eligible.filter { $0.due.map { $0 < day } ?? false }.sorted {
                if $0.due != $1.due { return $0.due! < $1.due! }
                return $0.id < $1.id
            }
        }
        dated = eligible.filter { $0.due == day }
        created = eligible.filter { $0.due == nil && $0.file == "journal/\(day).md" }
    }
}
