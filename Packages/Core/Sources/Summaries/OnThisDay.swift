import VaultFormat

/// Source-derived values only; no filesystem timestamps or index-specific types.
public struct OnThisDayInput: Sendable {
    public struct Mention: Sendable {
        public enum Kind: String, Sendable { case person, place }
        public let day: CalendarDate
        public let entity: String
        public let name: String
        public let kind: Kind
        public init(day: CalendarDate, entity: String, name: String, kind: Kind) {
            self.day = day
            self.entity = entity
            self.name = name
            self.kind = kind
        }
    }
    /// Written days that may share today's month and day, linked or not.
    public let days: [CalendarDate]
    /// Resolved body links to people and places, in source order within a day.
    public let mentions: [Mention]
    public init(days: [CalendarDate] = [], mentions: [Mention] = []) {
        self.days = days
        self.mentions = mentions
    }
}

/// The nearest earlier year that has a person or a place on today's month and day.
public struct OnThisDay: Sendable, Equatable {
    public struct Entity: Sendable, Equatable {
        public let id: String
        public let name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    public static let peopleLimit = 2

    public let day: CalendarDate
    /// First distinct people in source order, at most ``peopleLimit``.
    public let people: [Entity]
    /// First place in source order.
    public let place: Entity?
    /// Earlier years, besides ``day``, that also have a person or a place.
    public let otherYears: Int

    public init(day: CalendarDate, people: [Entity], place: Entity?, otherYears: Int) {
        self.day = day
        self.people = people
        self.place = place
        self.otherYears = otherYears
    }

    /// 29 February has no same day in a common year, so it only matches another 29 February.
    public static func select(today: CalendarDate, data: OnThisDayInput) -> Self? {
        let days = Set(data.days.filter { $0.month == today.month && $0.day == today.day && $0 < today })
        var linked: [Self] = []
        for day in days.sorted(by: >) {
            var people: [Entity] = []
            var place: Entity?
            for mention in data.mentions where mention.day == day {
                switch mention.kind {
                case .person:
                    guard people.count < peopleLimit, !people.contains(where: { $0.id == mention.entity }) else {
                        continue
                    }
                    people.append(Entity(id: mention.entity, name: mention.name))
                case .place:
                    if place == nil { place = Entity(id: mention.entity, name: mention.name) }
                }
            }
            guard !people.isEmpty || place != nil else { continue }
            linked.append(Self(day: day, people: people, place: place, otherYears: 0))
        }
        guard let nearest = linked.first else { return nil }
        return Self(day: nearest.day, people: nearest.people, place: nearest.place, otherYears: linked.count - 1)
    }
}
