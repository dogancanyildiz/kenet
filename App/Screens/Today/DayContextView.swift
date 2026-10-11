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
    @State private var destination: CalendarDate?
    @Environment(\.locale) private var locale

    init(store: IndexStore, today: CalendarDate, @ViewBuilder following: @escaping () -> Following) {
        self.today = today
        self.following = following
        _onThisDay = State(initialValue: OnThisDayModel(store: store))
    }

    var body: some View {
        let entry = onThisDay.entry
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            if let entry {
                // One row per context line, in reading order.
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    onThisDayRow(
                        OnThisDayPresentation(entry: entry, today: today, locale: locale), day: entry.day)
                }
            }
            following()
        }
        .preference(key: DayContextReadyKey.self, value: onThisDay.hasLoaded)
        .task(
            id: DayContextLoadKey(
                today: today, vault: onThisDay.store.vaultURL, revision: onThisDay.store.lastUpdated)
        ) { await onThisDay.load(today: today) }
        .navigationDestination(item: $destination) { DayView(store: onThisDay.store, date: $0) }
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
}

/// Reloads on a new day, another vault, or a new index publication.
private struct DayContextLoadKey: Hashable {
    let today: CalendarDate
    let vault: URL?
    let revision: Date?
}
