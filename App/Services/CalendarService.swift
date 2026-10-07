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
    @ObservationIgnored private let source: any CalendarEventSource
    @ObservationIgnored private var revision = 0

    init(source: any CalendarEventSource = EventKitCalendarSource()) {
        self.source = source
        authorization = source.authorization
        source.onChange = { [weak self] in Task { await self?.refresh() } }
    }

    func events(on day: CalendarDate) -> [CalendarEvent] { days[day] ?? [] }
    func showsSection(on day: CalendarDate) -> Bool {
        authorization.canRequest || (authorization.canRead && (!events(on: day).isEmpty || errorText != nil))
    }

    func load(_ day: CalendarDate, timeZone: TimeZone = .current) async {
        loadedDays.insert(day)
        await fetch(day, timeZone: timeZone)
    }

    /// Called on store changes and each return to the foreground, including permission changes in Settings.
    func refresh() async {
        revision += 1
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
