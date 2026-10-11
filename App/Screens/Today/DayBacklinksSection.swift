import SwiftUI
import VaultFormat
import VaultIndex

/// Preference key for test hosts waiting for backlinks to finish loading.
struct DayBacklinksReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Mounts the backlinks section below this view. When empty, adds zero section spacing.
    @ViewBuilder func dayBacklinks(store: IndexStore, date: CalendarDate) -> some View {
        DayBacklinksSection(store: store, date: date) { self }
    }
}

/// A section listing incoming wikilinks to a day from notes, entities, and other days.
/// Wraps preceding content so that when empty, it leaves no section gap in the outer layout.
struct DayBacklinksSection<Preceding: View>: View {
    let store: IndexStore
    let date: CalendarDate
    @ViewBuilder var preceding: () -> Preceding
    @State private var model: DayBacklinksModel
    @State private var destination: DayBacklinkDestination?
    @State private var linkDestination: EntityLinkDestination?
    @Environment(\.locale) private var locale

    init(store: IndexStore, date: CalendarDate, @ViewBuilder preceding: @escaping () -> Preceding) {
        self.store = store
        self.date = date
        self.preceding = preceding
        _model = State(initialValue: DayBacklinksModel(store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            preceding()
            if !model.items.isEmpty {
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    SectionHeader(
                        title: String(
                            localized: "Bu güne bağlananlar",
                            bundle: PresentationLocalization.bundle(locale), locale: locale),
                        count: model.items.count
                    )
                    ForEach(model.items) { item in
                        backlinkRow(item)
                    }
                }
            }
        }
        .preference(key: DayBacklinksReadyKey.self, value: model.hasLoaded)
        .task(
            id: DayBacklinksLoadKey(
                day: date, vault: store.vaultURL, revision: store.lastUpdated)
        ) {
            await model.load(day: date)
        }
        .navigationDestination(item: $destination) { dest in
            destinationView(for: dest)
        }
        .entityLinkSheet($linkDestination, store: store)
    }

    /// Another day is named by its date, written the way the app writes dates; the index
    /// hands it over as the file's ISO date.
    private func title(of item: DayBacklinkItem) -> String {
        guard item.sourceKind == "day", let day = CalendarDate(item.sourceTitle) else { return item.sourceTitle }
        return LocalDay.instant(for: day).formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    private func backlinkRow(_ item: DayBacklinkItem) -> some View {
        Button {
            destination = item.destination
        } label: {
            MarginRow(kind: .vault, time: nil) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title(of: item))
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                    InkLinkedText(segments: item.segments, openURL: { openLink($0) })
                }
            }
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.dayBacklink")
        .accessibilityLabel(Text(verbatim: "\(title(of: item)), \(item.text)"))
    }

    @ViewBuilder
    private func destinationView(for dest: DayBacklinkDestination) -> some View {
        switch dest {
        case .note(let file):
            SearchNoteView(store: store, file: file)
        case .entity(let file):
            if let entity = store.content.entities.first(where: { $0.id == file }) {
                EntityView(store: store, entity: entity)
            } else {
                ContentUnavailableView(
                    "Sonuç artık mevcut değil", systemImage: "doc.questionmark")
            }
        case .day(let day):
            DayView(store: store, date: day)
        }
    }

    private func openLink(_ url: URL) {
        linkDestination = EntityLinkDestination.from(url: url, entities: store.content.entities)
    }
}

extension DayBacklinksSection where Preceding == EmptyView {
    init(store: IndexStore, date: CalendarDate) {
        self.init(store: store, date: date) { EmptyView() }
    }
}

private struct DayBacklinksLoadKey: Hashable {
    let day: CalendarDate
    let vault: URL?
    let revision: Date?
}
