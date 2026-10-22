import VaultFormat

extension GraphMentions {
    /// An unordered pair stored in lexical order.
    public struct Pair: Hashable, Sendable {
        public let first: String
        public let second: String

        public init(first: String, second: String) {
            self.first = min(first, second)
            self.second = max(first, second)
        }
    }

    /// Counts distinct dates with a shared block, after restricting group members to visible entities.
    public static func cooccurrenceWeights(days: [Day], including ids: Set<String>) -> [Pair: Int] {
        var dates: [Pair: Set<CalendarDate>] = [:]
        for day in days {
            for group in day.groups {
                let members = Set(group).intersection(ids).sorted()
                for (index, first) in members.enumerated() {
                    for second in members.dropFirst(index + 1) {
                        dates[Pair(first: first, second: second), default: []].insert(day.date)
                    }
                }
            }
        }
        return dates.mapValues(\.count)
    }
}
