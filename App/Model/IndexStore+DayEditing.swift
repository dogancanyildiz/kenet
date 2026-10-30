import Foundation
import VaultFormat
import VaultStore

extension IndexStore {
    /// Replaces the day's Journal section. With `base`, the section on disk must still be `base`
    /// when the write's turn comes: a write queued before it (a day copy merge, another edit) may
    /// have changed it after the caller read it, and replacing it would erase those lines.
    /// A changed section is `staleTarget`, and nothing is written.
    func changeJournal(on day: CalendarDate, to text: String, base: String? = nil) async throws {
        try await performEdit(path: "journal/\(day).md") { writer in
            if let base {
                let document: RawDocument
                do { document = try await writer.dayDocument(for: day) } catch CocoaError.fileReadNoSuchFile {
                    document = RawDocument(bytes: [])
                }
                guard try JournalRecognition.body(of: document).utf8.elementsEqual(base.utf8) else {
                    throw VaultStoreError.staleTarget
                }
            }
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
