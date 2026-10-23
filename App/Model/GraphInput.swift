import VaultFormat
import VaultIndex

struct GraphInput: Sendable, Equatable {
    typealias Day = GraphMentions.Day
    /// Built-in entity kinds the graph always reads; custom types join them on request.
    static let kinds: Set<String> = ["person", "place"]
    var entities: [EntitySummary] = []
    var totals: [String: Int] = [:]
    var days: [Day] = []
    /// Custom type ID to its singular name, for each custom type read.
    var typeNames: [String: String] = [:]
    init() {}
    /// - Parameters:
    ///   - entities: The read model's entities; only ``kinds`` and the types of `typeNames` are kept.
    ///   - typeNames: The custom types read, by ID (none: people and places only).
    init(entities: [EntitySummary], mentions: GraphMentions, typeNames: [String: String] = [:]) {
        let kinds = Self.kinds.union(typeNames.keys)
        self.entities = entities.filter { kinds.contains($0.kind) }
        totals = mentions.totals
        days = mentions.days
        self.typeNames = typeNames
    }
}
