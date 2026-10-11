import Foundation
import Summaries
import VaultFormat

/// One person the reminder can see. The caller supplies the latest encounter on or before the
/// planning day; this type does not read the clock or the vault.
struct CadenceReminderPerson: Sendable, Equatable {
    var id: String
    var name: String
    var lastDay: CalendarDate?
    var cadence: PersonCadence
}

/// One `people-` request handed to the system, and the people its body counts.
struct CadenceReminderAssignment: Equatable, Sendable {
    var day: CalendarDate
    /// The instant the request fires. Kept so a later change of the reminder time or of the
    /// time zone cannot move a request that has already fired, or fire one that was withdrawn.
    var date: Date
    var personIDs: [String]
}

/// Device record of one vault's cadence reminders.
struct CadenceReminderMemory: Equatable, Sendable {
    /// The latest day a reminder that counted the person has fired.
    var fired: [String: CalendarDate] = [:]
    /// Requests of the current plan that had not fired when the plan was written.
    var pending: [CadenceReminderAssignment] = []

    /// Every replan withdraws the pending requests. Those whose instant has passed have fired
    /// (the app cannot observe delivery while it is closed); the later ones never will.
    func settled(at now: Date) -> CadenceReminderMemory {
        var result = CadenceReminderMemory(fired: fired)
        for request in pending where request.date <= now {
            for id in request.personIDs where result.fired[id].map({ $0 < request.day }) ?? true {
                result.fired[id] = request.day
            }
        }
        return result
    }
}

/// Device record of cadence reminders, keyed by vault path. Nothing is written into the vault.
struct CadenceReminderHistory: Equatable, Sendable {
    static let storageKey = "journal.notifications.cadenceReminders.v1"

    private(set) var vaults: [String: CadenceReminderMemory] = [:]

    init() {}

    init(from defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode([String: StoredVault].self, from: data)
        else { return }
        vaults = stored.mapValues { vault in
            var memory = CadenceReminderMemory()
            for (id, day) in vault.fired { memory.fired[id] = CalendarDate(day) }
            memory.pending = vault.pending.compactMap { request in
                CalendarDate(request.day).map {
                    CadenceReminderAssignment(
                        day: $0, date: Date(timeIntervalSince1970: request.at), personIDs: request.people)
                }
            }
            return memory
        }
    }

    static func read(from defaults: UserDefaults, vaultID: String?) -> CadenceReminderMemory {
        CadenceReminderHistory(from: defaults).memory(vaultID: vaultID)
    }

    func memory(vaultID: String?) -> CadenceReminderMemory {
        vaultID.flatMap { vaults[$0] } ?? CadenceReminderMemory()
    }

    /// Settles every vault, not only the open one: a replan withdraws all pending `people-`
    /// requests, so a plan left behind by another vault must not count as fired later.
    mutating func settle(at now: Date) {
        vaults = vaults.mapValues { $0.settled(at: now) }
    }

    /// Replaces the open vault's pending plan. `known` is the people who can still be reminded;
    /// records of anyone else (renamed, deleted, rhythm removed) are dropped so the record
    /// cannot outgrow the vault. Nil keeps them: the people were not read this time.
    mutating func record(_ pending: [CadenceReminderAssignment], known: Set<String>?, vaultID: String?) {
        guard let vaultID else { return }
        var memory = vaults[vaultID] ?? CadenceReminderMemory()
        if let known { memory.fired = memory.fired.filter { known.contains($0.key) } }
        memory.pending = pending
        vaults[vaultID] = memory
    }

    func persist(in defaults: UserDefaults) {
        let stored = vaults.filter { !$0.value.fired.isEmpty || !$0.value.pending.isEmpty }.mapValues { memory in
            StoredVault(
                fired: memory.fired.mapValues(\.description),
                pending: memory.pending.map {
                    StoredRequest(day: $0.day.description, at: $0.date.timeIntervalSince1970, people: $0.personIDs)
                })
        }
        if stored.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private struct StoredRequest: Codable {
        var day: String
        var at: Double
        var people: [String]
    }

    private struct StoredVault: Codable {
        var fired: [String: String]
        var pending: [StoredRequest]
    }
}

/// Who is due on each injected day, assuming no new meeting. One list per day (the daily cap);
/// the body shows at most three names.
enum CadenceReminderPlan {
    static let nameLimit = 3
    static let minimumQuietDays = 3

    /// Floor of a quarter of the rhythm, and never under three days.
    static func quietDays(cadence: Int) -> Int {
        max(minimumQuietDays, cadence / 4)
    }

    /// `days` is the forward window in order, already limited to notifications that will fire.
    /// `lastNotified` is only days whose reminder has already fired.
    static func plan(
        people: [CadenceReminderPerson], days: [CalendarDate],
        lastNotified: [String: CalendarDate] = [:]
    ) -> [CalendarDate: [CadenceReminderPerson]] {
        var history = lastNotified
        var result: [CalendarDate: [CadenceReminderPerson]] = [:]
        for day in days {
            let due = due(people: people, on: day, lastNotified: history)
            if due.isEmpty { continue }
            result[day] = due
            for person in due { history[person.id] = day }
        }
        return result
    }

    static func due(
        people: [CadenceReminderPerson], on day: CalendarDate, lastNotified: [String: CalendarDate]
    ) -> [CadenceReminderPerson] {
        var seen = Set<String>()
        var rows: [CadenceReminderPerson] = []
        for person in people {
            guard seen.insert(person.id).inserted else { continue }
            guard let cadence = person.cadence.days else { continue }
            if person.cadence.isPaused { continue }
            if let until = person.cadence.snoozedUntil, day <= until { continue }
            guard let last = person.lastDay, last <= day else { continue }
            let elapsed = day.ordinal - last.ordinal
            guard elapsed >= cadence else { continue }
            if let notified = lastNotified[person.id], last < notified {
                if day.ordinal - notified.ordinal < quietDays(cadence: cadence) { continue }
            }
            rows.append(person)
        }
        rows.sort { lhs, rhs in
            let left = (day.ordinal - lhs.lastDay!.ordinal) - lhs.cadence.days!
            let right = (day.ordinal - rhs.lastDay!.ordinal) - rhs.cadence.days!
            if left != right { return left > right }
            return lhs.id < rhs.id
        }
        return rows
    }

    static func message(people: [CadenceReminderPerson], hideContent: Bool) -> (title: String, body: String) {
        let title = String(localized: "Görüşme zamanı")
        if hideContent {
            let count = people.count
            return (title, String(localized: "Görüşme zamanı gelen \(count) kişi var"))
        }
        let shown = people.prefix(nameLimit).map(\.name)
        let body: String
        switch people.count {
        case 1:
            body = shown[0]
        case 2:
            body = String(localized: "\(shown[0]) ve \(shown[1])")
        case 3:
            body = String(localized: "\(shown[0]), \(shown[1]) ve \(shown[2])")
        default:
            let extra = people.count - nameLimit
            body = String(
                localized: "\(shown[0]), \(shown[1]), \(shown[2]) ve \(extra) kişi daha")
        }
        return (title, body)
    }
}
