import VaultFormat
import VaultStore

extension IndexStore {
    func changeJournal(on day: CalendarDate, to text: String) async throws {
        try await performEdit(path: "journal/\(day).md") { writer in
            try await writer.changingJournal(on: day, to: text)
        }
    }

    func eventTarget(on day: CalendarDate, row: EventRow) async throws -> LineBlock {
        let document = try await dayDocument(for: day)
        guard let event = document.bodyLines.events.first(where: { $0.block.line == row.sourceLine }),
            event.block.lineRange.upperBound == row.sourceEnd,
            event.block.text.utf8.elementsEqual(row.sourceText.utf8),
            event.block.id == row.sourceIdentifier,
            event.time?.raw == row.time?.raw
        else {
            await refresh()
            throw VaultStoreError.staleTarget
        }
        return event.block
    }

    func changeEvent(on day: CalendarDate, target: LineBlock, to text: String) async throws {
        let path = "journal/\(day).md"
        try await performEdit(path: path) { writer in
            try await writer.changingText(of: target, at: path, to: text)
        }
    }

    func deleteEvent(on day: CalendarDate, target: LineBlock) async throws {
        let path = "journal/\(day).md"
        try await performEdit(path: path) { writer in
            try await writer.deletingBlock(target, at: path)
        }
    }
}
