/// A calendar participant as the caller read it, before any vault lookup.
public struct Attendee: Equatable, Sendable {
    /// The display name the calendar holds; it can be blank or an address.
    public let name: String
    /// Whether the calendar marks this participant as the device owner.
    public let isCurrentUser: Bool

    /// Creates a participant to match against known entities.
    public init(name: String, isCurrentUser: Bool = false) {
        self.name = name
        self.isCurrentUser = isCurrentUser
    }
}

/// Participants sorted by how surely each one names a known entity, in participant order.
public struct AttendeeMatch: Equatable, Sendable {
    /// A participant only one entity answers to.
    public struct Certain: Equatable, Sendable {
        /// The entity's own spelling of the matched name or alias.
        public let spelling: String
        /// The single matching entity.
        public let entity: KnownEntity
    }

    /// A participant several entities answer to; the user decides.
    public struct Ambiguous: Equatable, Sendable {
        /// The participant's name as the calendar spells it, trimmed.
        public let spelling: String
        /// Every matching entity, in the order the entities were supplied.
        public let candidates: [KnownEntity]
    }

    /// Participants with exactly one matching entity.
    public let certain: [Certain]
    /// Participants with more than one matching entity.
    public let ambiguous: [Ambiguous]
    /// Trimmed names no entity answers to.
    public let unknown: [String]
}

/// Sorts calendar participants against supplied entities without filesystem or framework access.
public enum AttendeeMatching {
    /// Compares whole names with the recognizer's keys; a blank name, an address and the device
    /// owner are never candidates, and a name repeated among the participants counts once.
    public static func match(_ attendees: [Attendee], entities: [KnownEntity]) -> AttendeeMatch {
        var certain: [AttendeeMatch.Certain] = []
        var ambiguous: [AttendeeMatch.Ambiguous] = []
        var unknown: [String] = []
        var seen: [String] = []
        for attendee in attendees where !attendee.isCurrentUser {
            let name = trimmed(attendee.name)
            let key = name.lowercased()
            guard !name.isEmpty, !name.contains("@"), !seen.contains(key) else { continue }
            seen.append(key)
            var files: Set<String> = []
            let candidates = entities.filter { $0.comparisonKeys.contains(key) && files.insert($0.file).inserted }
            if candidates.count > 1 {
                ambiguous.append(.init(spelling: name, candidates: candidates))
            } else if let entity = candidates.first {
                let index = entity.comparisonKeys.firstIndex(of: key)!
                certain.append(.init(spelling: ([entity.name] + entity.aliases)[index], entity: entity))
            } else {
                unknown.append(name)
            }
        }
        return AttendeeMatch(certain: certain, ambiguous: ambiguous, unknown: unknown)
    }

    private static func trimmed(_ name: String) -> String {
        let start = name.drop(while: \.isWhitespace)
        return String(start.dropLast(start.reversed().prefix(while: \.isWhitespace).count))
    }
}
