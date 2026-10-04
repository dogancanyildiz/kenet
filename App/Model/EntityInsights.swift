import VaultFormat

/// A journal mention is evidence of a recorded encounter, not proof of a meeting.
struct EntityInsights {
    let lastDay: CalendarDate?
    let firstDay: CalendarDate?
    let recentDayCount: Int
    let averageInterval: Double?
    let rows: [EntityTimelineRow]
    let people: [EntitySummary]
    let places: [EntitySummary]

    static func compute(path: String, content: VaultReadModel, today: CalendarDate) -> Self {
        let history = (content.entityTimeline[path] ?? []).filter { $0.date <= today }
        let dates = Set(history.map(\.date)).sorted()
        let last = dates.last
        let recent = dates.filter { today.ordinal - $0.ordinal < 90 }
        let interval: Double? =
            recent.count > 1
            ? Double(recent.last!.ordinal - recent.first!.ordinal) / Double(recent.count - 1) : nil
        let rows = history.filter { $0.date == last }.flatMap(\.rows)
            .sorted { ($0.file, $0.ordinal) < ($1.file, $1.ordinal) }
        // Same-day context includes separate events and journal paragraphs, excluding tasks/frontmatter.
        let days = content.days.filter { $0.date == last }
        let texts = days.flatMap { $0.events.map(\.text) + $0.journal.filter { $0.headingLevel == nil }.map(\.text) }
        let companions = Set(texts.flatMap { $0.spans.compactMap(\.destination) }).subtracting([path])
        let entities = content.entities.filter { companions.contains($0.id) }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
        return Self(
            lastDay: last, firstDay: dates.first, recentDayCount: recent.count, averageInterval: interval,
            rows: rows, people: entities.filter { $0.kind == "person" }, places: entities.filter { $0.kind == "place" })
    }
}

struct UnseenPerson: Identifiable {
    let entity: EntitySummary
    let lastDay: CalendarDate?
    let elapsedDays: Int?
    var id: String { entity.id }
}

struct UnseenPeople {
    let overdue: [UnseenPerson]
    let never: [UnseenPerson]
    static func compute(people: [EntitySummary], content: VaultReadModel, today: CalendarDate, threshold: Int) -> Self {
        var overdue: [UnseenPerson] = []
        var never: [UnseenPerson] = []
        for entity in people where entity.kind == "person" {
            let last = content.entityTimeline[entity.id]?.map(\.date).filter { $0 <= today }.max()
            let elapsed = last.map { today.ordinal - $0.ordinal }
            let person = UnseenPerson(entity: entity, lastDay: last, elapsedDays: elapsed)
            if let elapsed {
                if elapsed >= PeopleInsightsPreference.normalized(threshold) { overdue.append(person) }
            } else {
                never.append(person)
            }
        }
        overdue.sort {
            if $0.elapsedDays != $1.elapsedDays { return $0.elapsedDays! > $1.elapsedDays! }
            return $0.id < $1.id
        }
        never.sort { $0.entity.name == $1.entity.name ? $0.id < $1.id : $0.entity.name < $1.entity.name }
        return Self(overdue: overdue, never: never)
    }
}
