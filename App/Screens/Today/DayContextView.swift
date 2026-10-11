import Summaries
import SwiftUI
import VaultFormat

/// Preference for snapshot hosts waiting until the context lines finished loading.
struct DayContextReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Mounts today's context lines above this section. `today` is nil on a past day's page,
    /// which draws and queries nothing.
    @ViewBuilder func dayContext(store: IndexStore, today: CalendarDate?) -> some View {
        if let today {
            DayContextView(store: store, today: today) { self }
        } else {
            self
        }
    }
}

/// Today's context lines: what the vault itself recalls about this date. Each line appears only
/// when it has something to say. The area wraps the section below it so that, with no line, the
/// page keeps its layout: a mounted but empty sibling would still cost one section gap.
struct DayContextView<Following: View>: View {
    let today: CalendarDate
    @ViewBuilder var following: () -> Following
    @State private var onThisDay: OnThisDayModel
    @State private var importantDates: ImportantDatesModel
    @State private var destination: CalendarDate?
    @State private var entityDestination: EntitySummary?
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    init(store: IndexStore, today: CalendarDate, @ViewBuilder following: @escaping () -> Following) {
        self.today = today
        self.following = following
        _onThisDay = State(initialValue: OnThisDayModel(store: store))
        _importantDates = State(initialValue: ImportantDatesModel(store: store))
    }

    var body: some View {
        let entry = onThisDay.entry
        let rows = dateRows
        let shown = Array(rows.prefix(ImportantDateList.limit))
        let extra = rows.count - shown.count
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            if entry != nil || !shown.isEmpty {
                // One row per context line, in reading order.
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    if let entry {
                        onThisDayRow(
                            OnThisDayPresentation(entry: entry, today: today, locale: locale), day: entry.day)
                    }
                    ForEach(shown) { row in
                        importantDateRow(row)
                    }
                    if extra > 0 {
                        moreDatesRow(extra)
                    }
                }
            }
            following()
        }
        .preference(key: DayContextReadyKey.self, value: onThisDay.hasLoaded && importantDates.hasLoaded)
        .task(
            id: DayContextLoadKey(
                today: today, vault: onThisDay.store.vaultURL, revision: onThisDay.store.lastUpdated)
        ) {
            async let history: Void = onThisDay.load(today: today)
            async let dates: Void = importantDates.load(today: today)
            _ = await (history, dates)
        }
        .navigationDestination(item: $destination) { DayView(store: onThisDay.store, date: $0) }
        .navigationDestination(item: $entityDestination) { EntityView(store: importantDates.store, entity: $0) }
    }

    private var dateRows: [ImportantDateRow] {
        importantDates.entries.compactMap { entry in
            guard let name = importantDates.store.content.entities.first(where: { $0.id == entry.file })?.name else {
                return nil
            }
            return ImportantDateRow(entry: entry, name: name)
        }
    }

    private func onThisDayRow(_ text: OnThisDayPresentation, day: CalendarDate) -> some View {
        Button {
            destination = day
        } label: {
            MarginRow(kind: .vault, time: text.year) {
                Text(verbatim: text.names)
                    .foregroundStyle(.ink.text)
            } secondary: {
                Text(verbatim: text.caption)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text.spoken))
        .accessibilityIdentifier("today.onThisDay")
    }

    private func importantDateRow(_ row: ImportantDateRow) -> some View {
        let text = ImportantDatePresentation(entry: row.entry, name: row.name, locale: locale, timeZone: timeZone)
        return Button {
            entityDestination = importantDates.store.content.entities.first { $0.id == row.entry.file }
        } label: {
            MarginRow(kind: .vault, time: text.when) {
                Text(verbatim: text.name)
                    .foregroundStyle(.ink.text)
            } secondary: {
                Text(verbatim: text.caption)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text.spoken))
        .accessibilityIdentifier("today.importantDate")
    }

    private func moreDatesRow(_ extra: Int) -> some View {
        let text = ImportantDatePresentation.more(extra, locale: locale)
        return MarginRow(kind: .vault, time: nil) {
            Text(verbatim: text)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
        }
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityIdentifier("today.importantDatesMore")
    }
}

/// Reloads on a new day, another vault, or a new index publication.
private struct DayContextLoadKey: Hashable {
    let today: CalendarDate
    let vault: URL?
    let revision: Date?
}
