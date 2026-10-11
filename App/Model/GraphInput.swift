import VaultFormat
import VaultIndex

struct GraphInput: Sendable, Equatable {
    struct Day: Sendable, Equatable {
        let date: CalendarDate
        let mentions: [String: Int]
    }
    /// Entity kinds the graph draws as nodes.
    static let kinds: Set<String> = ["person", "place"]
    var entities: [EntitySummary] = []
    var totals: [String: Int] = [:]
    var days: [Day] = []
    init() {}
    /// - Parameter entities: The read model's entities; only ``kinds`` are kept.
    init(entities: [EntitySummary], mentions: GraphMentions) {
        self.entities = entities.filter { Self.kinds.contains($0.kind) }
        totals = mentions.totals
        days = mentions.days.map { Day(date: $0.date, mentions: $0.mentions) }
    }
}
