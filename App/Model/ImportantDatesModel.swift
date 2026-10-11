import Foundation
import Observation
import Summaries
import VaultFormat

/// Upcoming anniversaries. Fields are read from the index on demand, never from the read model.
@MainActor @Observable
final class ImportantDatesModel {
    let store: IndexStore
    private(set) var entries: [ImportantDate] = []
    /// True once a query for the current vault, day and window has answered (also with nothing).
    private(set) var hasLoaded = false
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var loaded: (root: URL?, today: CalendarDate, window: Int?)?

    init(store: IndexStore) {
        self.store = store
    }

    func load(today: CalendarDate, within windowDays: Int? = ImportantDates.windowDays) async {
        let id = UUID()
        request = id
        let root = store.vaultURL
        // A refresh of the same vault, day and window keeps the shown lines; another one never does.
        if loaded?.root != root || loaded?.today != today || loaded?.window != windowDays {
            entries = []
            hasLoaded = false
            loaded = nil
        }
        let result = try? await store.computeImportantDates(today, within: windowDays)
        guard request == id, root == store.vaultURL, !Task.isCancelled else { return }
        entries = result ?? []
        loaded = (root, today, windowDays)
        hasLoaded = true
    }

    func nearest(file: String) -> ImportantDate? {
        entries.first { $0.file == file }
    }
}

/// Today shows at most this many anniversary lines; the rest is one "and N more" line.
enum ImportantDateList {
    static let limit = 3

    static func partition(_ dates: [ImportantDate]) -> (shown: [ImportantDate], extra: Int) {
        let shown = Array(dates.prefix(limit))
        return (shown, dates.count - shown.count)
    }
}

struct ImportantDateRow: Identifiable, Equatable {
    let entry: ImportantDate
    let name: String
    var id: String { entry.file + "\n" + entry.key }
}

/// Display text for one Today line. Built from calendar fields only, so no time zone can shift the day.
struct ImportantDatePresentation: Equatable {
    let when: String
    let name: String
    let caption: String
    var spoken: String { when + ", " + name + ", " + caption }

    init(entry: ImportantDate, name: String, locale: Locale, timeZone: TimeZone) {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let bundle = PresentationLocalization.bundle(resolved)
        switch entry.daysUntil {
        case 0: when = String(localized: "Bugün", bundle: bundle, locale: resolved)
        case 1: when = String(localized: "Yarın", bundle: bundle, locale: resolved)
        default: when = Self.shortDate(entry.date, locale: resolved, timeZone: timeZone)
        }
        self.name = name
        caption = String(localized: "\(entry.key) · \(entry.year) yıl", bundle: bundle, locale: resolved)
    }

    static func more(_ count: Int, locale: Locale) -> String {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        return String(
            localized: "ve \(count) tarih daha", bundle: PresentationLocalization.bundle(resolved), locale: resolved)
    }

    static func shortDate(_ day: CalendarDate, locale: Locale, timeZone: TimeZone) -> String {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = resolved
        calendar.timeZone = timeZone
        let instant = LocalDay.instant(for: day, timeZone: timeZone)
        let base = Date.FormatStyle(locale: resolved, calendar: calendar, timeZone: timeZone)
        let style = TurkishSuffix.isTurkish(resolved) ? base.day().month(.abbreviated) : base.month(.abbreviated).day()
        return instant.formatted(style)
    }
}

/// The entity page names the next anniversary without the seven-day window.
struct EntityImportantDatePresentation: Equatable {
    let line: String

    init(entry: ImportantDate, locale: Locale, timeZone: TimeZone) {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let bundle = PresentationLocalization.bundle(resolved)
        let when = ImportantDatePresentation.shortDate(entry.date, locale: resolved, timeZone: timeZone)
        line = String(
            localized: "\(entry.key) · \(when) · \(entry.year) yıl", bundle: bundle, locale: resolved)
    }
}
