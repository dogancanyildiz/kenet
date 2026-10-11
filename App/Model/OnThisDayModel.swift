import Foundation
import Observation
import Summaries
import VaultFormat

/// Today's "on this day" line. History is read from the index on demand, never from the read model.
@MainActor @Observable
final class OnThisDayModel {
    let store: IndexStore
    private(set) var entry: OnThisDay?
    /// True once a query for the current vault and day has answered (also with nothing).
    private(set) var hasLoaded = false
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var loaded: (root: URL?, today: CalendarDate)?

    init(store: IndexStore) {
        self.store = store
    }

    func load(today: CalendarDate) async {
        let id = UUID()
        request = id
        let root = store.vaultURL
        // A refresh of the same vault and day keeps the shown line; another vault or day never does.
        if loaded?.root != root || loaded?.today != today {
            entry = nil
            hasLoaded = false
            loaded = nil
        }
        let result = try? await store.computeOnThisDay(today)
        guard request == id, root == store.vaultURL, !Task.isCancelled else { return }
        entry = result
        loaded = (root, today)
        hasLoaded = true
    }
}

/// Display text for ``OnThisDay``. Built from calendar fields only, so no time zone can shift it.
struct OnThisDayPresentation: Equatable {
    /// The past year, for the edge column.
    let year: String
    /// At most two people and one place.
    let names: String
    /// How long ago, then how many more years have something.
    let caption: String
    var spoken: String { caption + ", " + names }

    init(entry: OnThisDay, today: CalendarDate, locale: Locale) {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let bundle = PresentationLocalization.bundle(resolved)
        year = entry.day.year.formatted(.number.grouping(.never).locale(resolved))
        let people = entry.people.map(\.name).formatted(.list(type: .and).locale(resolved))
        if let place = entry.place?.name {
            names =
                people.isEmpty
                ? place : String(localized: "\(people) · \(place)", bundle: bundle, locale: resolved)
        } else {
            names = people
        }
        let ago = String(
            localized: "\(today.year - entry.day.year) yıl önce bugün", bundle: bundle, locale: resolved)
        if entry.otherYears > 0 {
            let more = String(localized: "ve \(entry.otherYears) yıl daha", bundle: bundle, locale: resolved)
            caption = String(localized: "\(ago) · \(more)", bundle: bundle, locale: resolved)
        } else {
            caption = ago
        }
    }
}
