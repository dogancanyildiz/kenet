import Foundation
import VaultFormat
import VaultStore

extension IndexStore {
    /// Replaces the day's Journal section. With `base`, the section on disk must still be `base`
    /// when the write runs: a write queued before it (a day copy merge, another edit) or another
    /// process (the share extension, the widget, Obsidian, iCloud) may have changed it after the
    /// caller read it, and replacing it would erase those lines. Core compares inside the
    /// coordinated write (`VaultStore.changingJournal(on:to:expectedBody:)`). A changed section is
    /// `staleTarget`, and nothing is written.
    func changeJournal(on day: CalendarDate, to text: String, base: String? = nil) async throws {
        try await performEdit(path: "journal/\(day).md") { writer in
            try await writer.changingJournal(on: day, to: text, expectedBody: base)
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

    /// The line the share extension wrote for `entry` (`ShareEntry.writtenLineID`) gets a new
    /// identifier when another file also holds its identifier (`VaultStore.givingUniqueIdentifier`):
    /// the extension checks a new identifier against its day file alone. Nothing else is renewed:
    /// a marker without the identifier, an identifier on more than one line of the day, a day that
    /// cannot be read now. Throws when the renewal write fails.
    func renewClashingIdentifier(of entry: ShareEntry) async throws {
        guard let id = entry.writtenLineID, let day = entry.calendarDay else { return }
        let document: RawDocument
        do { document = try await dayDocument(for: day) } catch { return }
        let body = document.bodyLines
        let lines = (body.tasks.map(\.block) + body.events.map(\.block)).filter { $0.id == id }
        guard lines.count == 1, let line = lines.first else { return }
        let path = "journal/\(day).md"
        let holders = try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .empty([])) {
            try $0.files(holdingIdentifier: id)
        }
        guard holders.contains(where: { $0 != path }) else { return }
        try await performEdit(path: path) { writer in
            try await writer.givingUniqueIdentifier(to: line, at: path)
        }
    }
}
