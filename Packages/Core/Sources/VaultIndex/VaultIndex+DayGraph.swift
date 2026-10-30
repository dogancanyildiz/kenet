import Foundation
import VaultFormat

extension VaultIndex {
    /// One day's graph: the links from `date`'s day files into entities of `kinds`. The rules and the
    /// row walk are ``graphMentions(kinds:)``'s (`graphRows`), restricted to one date: only that
    /// date's files are read. A day without such a link has no mentions.
    public func dayGraphMentions(on date: CalendarDate, kinds: Set<String>) throws -> GraphMentions.Day {
        guard !kinds.isEmpty else { return GraphMentions.Day(date: date, mentions: [:]) }
        let rows = try graphRows(kinds: kinds, date: date)
        return GraphMentions.Day(
            date: date, mentions: rows.mentionsByDate.values.reduce(into: [:]) { $0.merge($1, uniquingKeysWith: +) })
    }
}
