import Foundation
import Summaries
import VaultFormat
import VaultStore

/// A journal mention is evidence of a recorded encounter, not proof of a meeting.
struct EntityInsights {
    let lastDay: CalendarDate?
    let firstDay: CalendarDate?
    let recentDayCount: Int
    let averageInterval: Double?
    let rows: [EntityTimelineRow]
    let people: [EntitySummary]
    let places: [EntitySummary]

    /// `timeline` is the entity's own (`IndexStore.computeEntityTimeline(for:)`). `lastDay` is the
    /// day of `lastDay(in:today:)` (`IndexStore.computeDay(on:)`), whose other links are the
    /// same-day companions; another day gives none.
    static func compute(
        path: String, timeline: [EntityTimelineDay], lastDay: DaySummary?, entities: [EntitySummary],
        today: CalendarDate
    ) -> Self {
        let history = timeline.filter { $0.date <= today }
        let dates = Set(history.map(\.date)).sorted()
        let last = dates.last
        let recent = dates.filter { today.ordinal - $0.ordinal < 90 }
        let interval: Double? =
            recent.count > 1
            ? Double(recent.last!.ordinal - recent.first!.ordinal) / Double(recent.count - 1) : nil
        let rows = history.filter { $0.date == last }.flatMap(\.rows)
            .sorted { ($0.file, $0.ordinal) < ($1.file, $1.ordinal) }
        // Same-day context includes separate events and journal paragraphs, excluding tasks/frontmatter.
        let days = [lastDay].compactMap { $0 }.filter { $0.date == last }
        let texts = days.flatMap { $0.events.map(\.text) + $0.journal.filter { $0.headingLevel == nil }.map(\.text) }
        let companions = Set(texts.flatMap { $0.spans.compactMap(\.destination) }).subtracting([path])
        let entities = entities.filter { companions.contains($0.id) }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
        return Self(
            lastDay: last, firstDay: dates.first, recentDayCount: recent.count, averageInterval: interval,
            rows: rows, people: entities.filter { $0.kind == "person" }, places: entities.filter { $0.kind == "place" })
    }

    /// The newest timeline day on or before `today`: the day whose companions the card lists.
    static func lastDay(in timeline: [EntityTimelineDay], today: CalendarDate) -> CalendarDate? {
        timeline.map(\.date).filter { $0 <= today }.max()
    }
}

struct UnseenPerson: Identifiable {
    let entity: EntitySummary
    let lastDay: CalendarDate?
    let elapsedDays: Int?
    /// Days past the person's cadence, or past the fallback threshold. Nil when they were never met.
    let overdueDays: Int?
    var id: String { entity.id }
}

struct UnseenPeople {
    let overdue: [UnseenPerson]
    let never: [UnseenPerson]

    /// `lastEncounters` are as of `today` (`IndexStore.computeLastEncounters(asOf:)`). `cadences`
    /// defaults to empty, which keeps the fallback threshold for every person.
    static func compute(
        people: [EntitySummary], lastEncounters: [String: CalendarDate], today: CalendarDate, threshold: Int,
        cadences: [String: PersonCadence] = [:]
    ) -> Self {
        // A repeated id must not trap; the first entry wins.
        let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inputs = people.filter { $0.kind == "person" }.map { entity in
            CadencePerson(
                id: entity.id, name: entity.name, lastDay: lastEncounters[entity.id],
                cadence: cadences[entity.id] ?? .none)
        }
        let lastDays = Dictionary(inputs.map { ($0.id, $0.lastDay) }, uniquingKeysWith: { first, _ in first })
        let listed = MeetingCadence.list(
            people: inputs, today: today, fallbackThreshold: PeopleInsightsPreference.normalized(threshold))
        func row(_ listed: CadenceList.Row) -> UnseenPerson? {
            guard let entity = byID[listed.id] else { return nil }
            return UnseenPerson(
                entity: entity, lastDay: lastDays[listed.id] ?? nil, elapsedDays: listed.elapsedDays,
                overdueDays: listed.overdueDays)
        }
        return Self(overdue: listed.overdue.compactMap(row), never: listed.never.compactMap(row))
    }
}

/// List actions shared by the context menu and VoiceOver.
enum UnseenCadenceCommand: CaseIterable, Identifiable {
    case snoozeWeek
    case snoozeMonth
    case pause

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .snoozeWeek: "1 hafta ertele"
        case .snoozeMonth: "1 ay ertele"
        case .pause: "Duraklat"
        }
    }

    /// The inclusive snooze day, or nil for pause.
    func until(from today: CalendarDate) -> CalendarDate? {
        switch self {
        case .snoozeWeek: today.addingDays(7)
        case .snoozeMonth: today.addingMonths(1)
        case .pause: nil
        }
    }

    /// Writes the one field the command owns; nil on success, otherwise the message to show.
    /// A failed index update after saved bytes is reported, not retried.
    @MainActor
    func apply(path: String, today: CalendarDate, store: IndexStore) async -> String? {
        do {
            switch self {
            case .snoozeWeek, .snoozeMonth:
                guard let day = until(from: today) else { throw VaultStoreError.staleTarget }
                try await store.setField(at: path, key: PersonCadence.snoozeKey, value: .date(day))
            case .pause:
                try await store.setField(at: path, key: PersonCadence.pauseKey, value: .boolean(true))
            }
            return nil
        } catch {
            return DayEditError.message(for: error)
        }
    }

    /// "Sürdür": removes `cadence_paused` and nothing else.
    @MainActor
    static func resume(path: String, store: IndexStore) async -> String? {
        do {
            try await store.removeField(at: path, key: PersonCadence.pauseKey)
            return nil
        } catch {
            return DayEditError.message(for: error)
        }
    }
}

/// Rhythm, snooze and pause lines for the person insight card.
struct CadenceStatusPresentation: Equatable {
    var rhythm: String?
    var snooze: String?
    var paused: String?
    var showsResume: Bool

    init(cadence: PersonCadence, today: CalendarDate, locale: Locale, timeZone: TimeZone) {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let bundle = PresentationLocalization.bundle(resolved)
        if let days = cadence.days {
            rhythm = String(localized: "Ritim: \(days) günde bir", bundle: bundle, locale: resolved)
        }
        if let until = cadence.snoozedUntil, today <= until {
            let when = ImportantDatePresentation.shortDate(until, locale: resolved, timeZone: timeZone)
            snooze = String(localized: "\(when) tarihine kadar ertelendi", bundle: bundle, locale: resolved)
        }
        if cadence.isPaused {
            paused = String(localized: "Duraklatıldı", bundle: bundle, locale: resolved)
            showsResume = true
        } else {
            showsResume = false
        }
    }
}
