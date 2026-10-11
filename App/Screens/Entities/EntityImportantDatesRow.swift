import SwiftUI
import VaultFormat

/// Preference for snapshot hosts waiting until the entity anniversary line finished loading.
struct ImportantDatesReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// The nearest anniversary of one person or custom-type file. Nothing is drawn when there is none.
/// The query lives on ``EntityImportantDatesLoader``: a `List` drops an empty row, so a `.task`
/// on this view would never start.
struct EntityImportantDatesRow: View {
    let file: String
    let model: ImportantDatesModel
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        if let entry = model.nearest(file: file) {
            Text(verbatim: EntityImportantDatePresentation(entry: entry, locale: locale, timeZone: timeZone).line)
                .font(.ink.content)
                .foregroundStyle(.ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("entity.importantDate")
                .inkListRow()
        }
    }
}

/// Loads anniversaries from outside the list. Mount it on the page, not as a row.
struct EntityImportantDatesLoader: View {
    let model: ImportantDatesModel
    let file: String
    let enabled: Bool
    @Environment(\.timeZone) private var timeZone
    @Environment(\.clockNow) private var clockNow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(
                id: ImportantDatesLoadKey(
                    today: LocalDay.today(at: clockNow(), timeZone: timeZone), vault: model.store.vaultURL,
                    revision: model.store.lastUpdated, file: file, window: nil, enabled: enabled)
            ) {
                guard enabled else { return }
                await model.load(today: LocalDay.today(at: clockNow(), timeZone: timeZone), within: nil)
            }
    }
}

struct ImportantDatesLoadKey: Hashable {
    let today: CalendarDate
    let vault: URL?
    let revision: Date?
    let file: String
    let window: Int?
    let enabled: Bool
}
