import VaultFormat

/// Source-derived usage statistics for one entity.
public struct EntityUsage: Equatable, Sendable {
    /// The vault-relative entity path.
    public let file: String
    /// All resolved incoming link occurrences.
    public let totalCount: Int
    /// The most recent source journal date, if any.
    public let lastDate: CalendarDate?
    /// Other entity paths mapped to the number of shared journal days.
    public let cooccurrences: [String: Int]

    /// Creates immutable ranking data; missing usage is treated as zero.
    public init(file: String, totalCount: Int = 0, lastDate: CalendarDate? = nil, cooccurrences: [String: Int] = [:]) {
        self.file = file
        self.totalCount = totalCount
        self.lastDate = lastDate
        self.cooccurrences = cooccurrences
    }
}

/// Optional context supplied by the caller in addition to certain mentions in the text.
public struct RecognitionContext: Sendable {
    /// Whether all supplied text is already inside a code fence.
    public let insideFence: Bool
    /// Known entities already established by the caller, counted once by path.
    public let entities: [KnownEntity]

    /// Creates context without introducing index dependencies.
    public init(insideFence: Bool = false, entities: [KnownEntity] = []) {
        self.insideFence = insideFence
        self.entities = entities
    }
}
