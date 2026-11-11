import Foundation
import Observation
import VaultFormat

@MainActor @Observable
final class CalendarService {
    private(set) var authorization: CalendarAuthorization
    private(set) var isRequesting = false
    private(set) var errorText: String?
    private var days: [CalendarDate: [CalendarEvent]] = [:]
    private var loadedDays: Set<CalendarDate> = []
    /// The last failed write, shown in the sheet that asked for it.
    private(set) var writeErrorText: String?
    private(set) var isWriting = false
    /// Bumped after each write and store change, so pages that query on their own reload.
    private(set) var changeCount = 0
    /// Settings' calendar for new events, a device preference (decision 2026-11-11).
    var defaultCalendarID: String? {
        didSet { defaults.set(defaultCalendarID, forKey: Self.defaultCalendarKey) }
    }
    static let defaultCalendarKey = "calendar.defaultCalendarID"
    @ObservationIgnored private let source: any CalendarEventSource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var revision = 0

    init(source: any CalendarEventSource = EventKitCalendarSource(), defaults: UserDefaults = .standard) {
        self.source = source
        self.defaults = defaults
        authorization = source.authorization
        defaultCalendarID = defaults.string(forKey: Self.defaultCalendarKey)
        source.onChange = { [weak self] in Task { await self?.refresh() } }
    }

    func events(on day: CalendarDate) -> [CalendarEvent] { days[day] ?? [] }
    /// With read access the section always shows: it holds "Takvime etkinlik ekle".
    func showsSection(on day: CalendarDate) -> Bool {
        authorization.canRequest || authorization.canRead
    }

    /// Calendars that accept new events; empty without access or on failure.
    func writableCalendars() async -> [CalendarTarget] {
        guard source.authorization.canRead else { return [] }
        return (try? await source.writableCalendars()) ?? []
    }

    /// Settings' choice while it still names a writable calendar, else the system's.
    func resolvedDefaultCalendarID(among calendars: [CalendarTarget]) async -> String? {
        if let id = defaultCalendarID, calendars.contains(where: { $0.id == id }) { return id }
        return await source.systemDefaultCalendarID()
    }

    /// Writes `draft` to the calendar; true on success. The vault is never touched.
    func save(_ draft: CalendarEventDraft, editing: CalendarEvent? = nil, span: CalendarEditSpan = .thisEvent)
        async -> Bool
    {
        guard draft.canSave else { return false }
        return await write {
            var normalized = draft.normalized()
            if normalized.calendarID == nil, editing == nil { normalized.calendarID = defaultCalendarID }
            try await source.save(normalized, editing: editing, span: span)
        }
    }

    func delete(_ event: CalendarEvent, span: CalendarEditSpan = .thisEvent) async -> Bool {
        await write { try await source.delete(event, span: span) }
    }

    func clearWriteError() { writeErrorText = nil }

    /// Upcoming events naming the person (title or attendee), plus the birthday among them.
    /// Nil without read access.
    func personEvents(names: [String], from start: Date, days: Int = 365) async -> CalendarPersonEvents? {
        guard source.authorization.canRead else { return nil }
        guard let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: start),
            let all = try? await source.events(from: start, to: end)
        else { return nil }
        return CalendarPersonEvents(
            upcoming: CalendarPersonMatch.upcoming(all, names: names),
            birthday: CalendarBirthday.find(in: all, names: names))
    }

    private func write(_ body: () async throws -> Void) async -> Bool {
        guard source.authorization.canRead, !isWriting else { return false }
        isWriting = true
        writeErrorText = nil
        defer { isWriting = false }
        do {
            try await body()
            await refresh()
            return true
        } catch {
            writeErrorText = String(localized: "Etkinlik takvime yazılamadı.")
            return false
        }
    }

    func load(_ day: CalendarDate, timeZone: TimeZone = .current) async {
        loadedDays.insert(day)
        await fetch(day, timeZone: timeZone)
    }

    /// Called on store changes and each return to the foreground, including permission changes in Settings.
    func refresh() async {
        revision += 1
        changeCount += 1
        authorization = source.authorization
        errorText = nil
        guard authorization.canRead else {
            days = [:]
            return
        }
        let current = revision
        for day in loadedDays.sorted() {
            guard current == revision else { return }
            await fetch(day, timeZone: .current)
        }
    }

    func requestAccess() async {
        guard authorization.canRequest, !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            _ = try await source.requestFullAccess()
            await refresh()
        } catch {
            authorization = source.authorization
            errorText = String(localized: "Takvim izni alınamadı. Yeniden deneyebilirsin.")
        }
    }

    private func fetch(_ day: CalendarDate, timeZone: TimeZone) async {
        authorization = source.authorization
        guard authorization.canRead else {
            days = [:]
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let interval = calendar.dateInterval(of: .day, for: LocalDay.instant(for: day, timeZone: timeZone)) else {
            return
        }
        let current = revision
        do {
            let result = try await source.events(from: interval.start, to: interval.end)
            guard current == revision, source.authorization.canRead else { return }
            errorText = nil
            days[day] = result.filter {
                $0.start < interval.end
                    && ($0.end > interval.start || ($0.start >= interval.start && $0.end == $0.start))
            }.sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.title != $1.title { return $0.title < $1.title }
                return $0.id < $1.id
            }
        } catch {
            guard current == revision else { return }
            days[day] = []
            errorText = String(localized: "Takvim etkinlikleri okunamadı.")
        }
    }
}

struct CalendarPersonEvents: Equatable, Sendable {
    let upcoming: [CalendarEvent]
    let birthday: CalendarEvent?
}
