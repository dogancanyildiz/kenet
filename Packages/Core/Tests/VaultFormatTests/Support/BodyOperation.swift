import Testing

@testable import VaultFormat

struct BodyOperation {
    let json: JSONValue

    func apply(to document: RawDocument) throws -> RawDocument {
        let operation = try #require(json["operation"]?.stringValue)
        let text = json["text"]?.stringValue ?? ""
        let id = json["id"]?.stringValue
        let time: LineClock?
        if let clock = json["time"], clock != .null {
            time = try LineClock(
                hour: try #require(clock["hour"]?.intValue), minute: try #require(clock["minute"]?.intValue))
        } else {
            time = nil
        }
        if operation == "add-event" { return try document.addingEvent(text: text, id: try #require(id), time: time) }
        if operation == "add-task" { return try document.addingTask(text: text, id: try #require(id)) }
        func date(_ key: String) -> CalendarDate? { json[key]?.stringValue.flatMap { CalendarDate($0) } }
        func priority() -> TaskPriority? {
            switch json["priority"]?.stringValue {
            case "high": .high
            case "medium": .medium
            case "low": .low
            case "🔺": .other("🔺")
            default: nil
            }
        }
        if operation == "add-task-fields" {
            return try document.addingTask(
                text: text, id: try #require(id), due: date("due"), start: date("start"),
                priority: priority(), project: json["project"]?.stringValue)
        }
        let line = try #require(json["line"]?.intValue) - 1
        let body = document.bodyLines
        let block = try #require((body.events.map(\.block) + body.tasks.map(\.block)).first { $0.line == line })
        switch operation {
        case "text": return try document.changingText(of: block, to: text, newID: id)
        case "delete": return try document.deletingBlock(block)
        case "status":
            let task = try #require(body.tasks.first { $0.block == block })
            let statusName = try #require(json["status"]?.stringValue)
            let status = try #require(TaskStatus(rawValue: statusName))
            return try document.changingStatus(of: task, to: status, completionDate: date("completionDate"), newID: id)
        case "due", "start", "priority", "project":
            let task = try #require(body.tasks.first { $0.block == block })
            switch operation {
            case "due": return try document.settingTaskDueDate(of: task, to: date("due"), newID: id)
            case "start": return try document.settingTaskStartDate(of: task, to: date("start"), newID: id)
            case "priority": return try document.settingTaskPriority(of: task, to: priority(), newID: id)
            default: return try document.settingTaskProject(of: task, to: json["project"]?.stringValue, newID: id)
            }
        case "time":
            return try document.changingTime(
                of: try #require(body.events.first { $0.block == block }), to: time, newID: id)
        case "stale-delete", "stale-text":
            let replacement = RawDocument(bytes: Array(try #require(json["replacement"]?.stringValue).utf8))
            if operation == "stale-delete" { return try replacement.deletingBlock(block) }
            return try replacement.changingText(of: block, to: text)
        case "wrong-status":
            return try document.changingStatus(of: TaskLine(block: block, rawStatus: " ", status: .todo), to: .done)
        case "wrong-time":
            return try document.changingTime(
                of: EventLine(block: block, time: EventTime(hour: 9, minute: 0, raw: "09:00")),
                to: LineClock(hour: 9, minute: 0))
        case "stale":
            let changed = try document.changingText(of: block, to: "Su")
            return try changed.changingText(of: block, to: text)
        default: throw FixtureError.unreadable(path: "operation.json", reason: operation)
        }
    }

    static func check(_ json: JSONValue, description: JSONValue, before: RawDocument, name: String) throws {
        #expect(
            Set(json.keys).isSubset(of: [
                "operation", "line", "text", "id", "time", "status", "replacement", "completionDate", "due", "start",
                "priority", "project",
            ]))
        let operation = Self(json: json)
        if let error = description["expectedError"] {
            #expect(try Fixtures.fileNames(in: "write/\(name)") == ["input.md", "operation.json"])
            #expect { try operation.apply(to: before) } throws: { ($0 as? EditError)?.fixtureName == error.stringValue }
        } else {
            #expect(try Fixtures.fileNames(in: "write/\(name)") == ["expected.md", "input.md", "operation.json"])
            let expected = try Fixtures.bytes(at: "write/\(name)/expected.md")
            let after = try operation.apply(to: before)
            #expect(after.serialized() == expected, "\(name): \(visible(after.serialized()))")
            #expect(after == RawDocument(bytes: expected))
            checkUntouched(before, after, json: json)
        }
    }

    /// Matches surviving lines independently of writer offsets, including their exact terminators.
    static func checkUntouched(_ before: RawDocument, _ after: RawDocument, json: JSONValue) {
        let op = json["operation"]?.stringValue
        let line = (json["line"]?.intValue ?? 0) - 1
        let target = (before.bodyLines.events.map(\.block) + before.bodyLines.tasks.map(\.block)).first {
            $0.line == line
        }
        var remaining = after.lines
        for index in before.lines.indices {
            if let target, (op == "delete" || op == "time") && target.lineRange.contains(index) { continue }
            if index == line { continue }
            let source = before.lines[index]
            if let match = remaining.firstIndex(of: source) {
                remaining.remove(at: match)
            } else {
                #expect(
                    source.ending == nil
                        && after.lines.contains {
                            $0.content == source.content && $0.ending == before.lineEndingForNewLines
                        }, "untouched line \(index + 1)")
            }
        }
    }
}

extension JSONValue {
    var intValue: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }
}
