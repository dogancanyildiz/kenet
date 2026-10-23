import Foundation
import VaultFormat

extension VaultIndex {
    /// One day's graph: the links from `date`'s day files into entities of `kinds`, and the entity
    /// sets sharing one of that day's blocks or paragraph segments. The rules and the row walk are
    /// ``graphMentions(kinds:)``'s (`graphRows`), restricted to one date: only that date's files are
    /// read. A day without such a link has no mentions and no groups.
    public func dayGraphMentions(on date: CalendarDate, kinds: Set<String>) throws -> GraphMentions.Day {
        guard !kinds.isEmpty else { return GraphMentions.Day(date: date, mentions: [:]) }
        let rows = try graphRows(kinds: kinds, date: date)
        // Same-date files share the day, so identical groups from them count once.
        let groups = rows.blocksByDate.values.reduce(into: Set<[String]>()) { $0.formUnion(Self.graphGroups($1)) }
        return GraphMentions.Day(
            date: date, mentions: rows.mentionsByDate.values.reduce(into: [:]) { $0.merge($1, uniquingKeysWith: +) },
            groups: groups.sorted { $0.lexicographicallyPrecedes($1) })
    }
}
