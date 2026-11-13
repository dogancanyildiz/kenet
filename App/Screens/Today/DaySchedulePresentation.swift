import SwiftUI
import VaultFormat

/// One row on the past-day timed schedule (`DaySchedulePresentation`).
struct DayScheduleEntry: Identifiable, Sendable {
    enum Kind: Sendable {
        case event(EventRow)
        case task(TaskRow)
    }

    let id: String
    let time: EventTime?
    let fileOrder: Int
    let kind: Kind
}

/// Pure chronological sorting for a past day's schedule: timed items sorted by `EventTime`
/// (ties preserve vault file order), untimed items grouped at the end in vault file order.
struct DaySchedulePresentation: Sendable {
    let timed: [DayScheduleEntry]
    let untimed: [DayScheduleEntry]

    var isEmpty: Bool {
        timed.isEmpty && untimed.isEmpty
    }

    var allOrdered: [DayScheduleEntry] {
        timed + untimed
    }

    init(entries: [DayScheduleEntry]) {
        let withTime = entries.filter { $0.time != nil }
        let withoutTime = entries.filter { $0.time == nil }
        timed = withTime.sorted { lhs, rhs in
            guard let lt = lhs.time, let rt = rhs.time else {
                return lhs.fileOrder < rhs.fileOrder
            }
            if lt.hour != rt.hour {
                return lt.hour < rt.hour
            }
            if lt.minute != rt.minute {
                return lt.minute < rt.minute
            }
            return lhs.fileOrder < rhs.fileOrder
        }
        untimed = withoutTime.sorted { $0.fileOrder < $1.fileOrder }
    }

    /// Events are the day file's; tasks written in `dayFile` take their place among them by line,
    /// so "Saatsiz" follows the file. Tasks from other files (due on the day) come after, in the
    /// order given.
    init(events: [EventRow], tasks: [TaskRow], dayFile: String? = nil) {
        var combined: [DayScheduleEntry] = events.map { event in
            DayScheduleEntry(
                id: "event-\(event.id)-\(event.sourceLine)", time: event.time,
                fileOrder: event.sourceLine, kind: .event(event))
        }
        let lastLine = (events.map(\.sourceLine) + tasks.map(\.sourceLine)).max() ?? 0
        for (index, task) in tasks.enumerated() {
            let inDayFile = dayFile != nil && task.file == dayFile
            combined.append(
                DayScheduleEntry(
                    id: "task-\(task.id)", time: Self.extractLeadingTime(from: task.text.plainText),
                    fileOrder: inDayFile ? task.sourceLine : lastLine + 1 + index, kind: .task(task)))
        }
        self.init(entries: combined)
    }

    static func extractLeadingTime(from text: String) -> EventTime? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5 else { return nil }
        let prefix = String(trimmed.prefix(5))
        let rest = trimmed.dropFirst(5)
        guard rest.isEmpty || rest.first == " " else { return nil }
        return RawDocument(bytes: Array("## Events\n- \(prefix) item".utf8)).bodyLines.events.first?.time
    }

    static func strippingLeadingTime(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard extractLeadingTime(from: trimmed) != nil else { return text }
        return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }

    static func splitSegmentsByLine(_ segments: [InkLinkSegment]) -> [[InkLinkSegment]] {
        var lines: [[InkLinkSegment]] = [[]]
        for segment in segments {
            if segment.kind == .plain, segment.text.contains("\n") {
                let parts = segment.text.split(separator: "\n", omittingEmptySubsequences: false)
                for (index, part) in parts.enumerated() {
                    if index > 0 {
                        lines.append([])
                    }
                    let text: String
                    if index > 0 {
                        text = String(part).replacingOccurrences(
                            of: #"^\s*(?:[-*]\s+)?"#, with: "", options: .regularExpression)
                    } else {
                        text = String(part)
                    }
                    if !text.isEmpty {
                        lines[lines.count - 1].append(
                            InkLinkSegment(id: "\(segment.id)-\(index)", text: text, kind: .plain))
                    }
                }
            } else {
                lines[lines.count - 1].append(segment)
            }
        }
        let nonEmpty = lines.filter { !$0.isEmpty }
        return nonEmpty.isEmpty ? [[]] : nonEmpty
    }
}
