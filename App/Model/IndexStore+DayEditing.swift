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

    /// The lines the share extension wrote for `entry` whose identifier another file also holds
    /// get a new one (`VaultStore.givingUniqueIdentifier`). The extension checks a new identifier
    /// against its day file alone. A line without a clash, or a day that cannot be read now, is
    /// left as it is; the duplicate rule still applies to it.
    func renewClashingIdentifiers(of entry: ShareEntry) async {
        guard let day = entry.calendarDay, let document = try? await dayDocument(for: day) else { return }
        let path = "journal/\(day).md"
        for line in entry.matchingLines(in: document, text: entry.text) {
            guard let id = line.id else { continue }
            let holders = try? await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .empty([])) {
                try $0.files(holdingIdentifier: id)
            }
            guard let holders, holders.contains(where: { $0 != path }) else { continue }
            try? await performEdit(path: path) { writer in
                try await writer.givingUniqueIdentifier(to: line, at: path)
            }
        }
    }
}
