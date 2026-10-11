import VaultFormat

extension VaultStore {
    /// Appends text to the end of the day's Journal, reading the current disk document and writing file first.
    ///
    /// The lines are text: `RawDocument.appendingJournalLines` splits, trims and marks them so they add no
    /// task, event or section. Blank lines alone write nothing and do not create a missing day.
    @discardableResult
    public func appendingJournal(on date: CalendarDate, lines: [String]) async throws -> RawDocument {
        try await perform {
            try self.edit(
                self.dayFilePath(for: date), date: date, createDay: lines.contains { !$0.allSatisfy(\.isWhitespace) }
            ) {
                try $0.appendingJournalLines(lines)
            }
        }
    }
}
