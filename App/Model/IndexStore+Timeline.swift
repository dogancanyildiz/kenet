import VaultFormat
import VaultStore

enum TimelineWriteError: Error { case partiallySaved }

extension IndexStore {
    /// The second write uses the first write's reparsed target, including any repaired identifier.
    func setTimelineDates(_ row: TaskRow, to dates: TimelineDates) async throws {
        guard dates.isValid else { throw EditError.invalidValue }
        let root = vaultURL
        let target = try await taskTarget(row)
        guard root == vaultURL else { throw VaultStoreError.staleTarget }
        let writesStart = row.start != dates.start
        let writesDue = row.due != dates.due
        guard writesStart || writesDue else { return }
        do {
            try await performEdit(path: row.file) { writer in
                var current = target
                var savedFirst = false
                // Extending the right edge first avoids a temporarily reversed range when moving right.
                let dueFirst =
                    writesStart && writesDue
                    && dates.start.map { start in
                        row.due.map { start > $0 } ?? false
                    } == true
                let edges: [TimelineDates.Edge] = dueFirst ? [.due, .start] : [.start, .due]
                for edge in edges where edge == .start ? writesStart : writesDue {
                    do {
                        let document: RawDocument
                        if edge == .start {
                            document = try await writer.settingTaskStartDate(of: current, at: row.file, to: dates.start)
                        } else {
                            document = try await writer.settingTaskDueDate(of: current, at: row.file, to: dates.due)
                        }
                        savedFirst = true
                        guard let next = document.bodyLines.tasks.first(where: { $0.block.line == current.block.line })
                        else {
                            throw TimelineWriteError.partiallySaved
                        }
                        current = next
                    } catch {
                        if savedFirst { throw TimelineWriteError.partiallySaved }
                        if case VaultStoreError.indexUpdateFailed = error, writesStart && writesDue {
                            throw TimelineWriteError.partiallySaved
                        }
                        throw error
                    }
                }
            }
        } catch {
            // Includes a stale second write, a partial index failure and a single saved-but-unindexed date.
            await refresh()
            throw error
        }
    }
}
