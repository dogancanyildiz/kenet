import SwiftUI
import WidgetKit

@main
struct JournalWidgets: WidgetBundle {
    var body: some Widget {
        GoalChainWidget()
    }
}

/// Home-screen chain widget (small, medium). It reads the snapshot the app writes into the App
/// Group and nothing else: no SQLite, no vault, no writes. A tap opens the app with a
/// ``WidgetLink``; the app marks the goal through its App Intent path.
struct GoalChainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.goalChain, provider: GoalChainProvider()) { entry in
            GoalChainEntryView(entry: entry)
        }
        .configurationDisplayName("Zincir")
        .description("Günlük hedeflerin ve zincirlerin. Dokunduğun hedefi Kenet işaretler.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GoalChainEntry: TimelineEntry {
    let date: Date
    let day: WidgetSnapshot.Day?
    let vaultID: String
}

struct GoalChainProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoalChainEntry {
        GoalChainEntry(date: Date(), day: nil, vaultID: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (GoalChainEntry) -> Void) {
        completion(entries(from: Date()).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoalChainEntry>) -> Void) {
        // The app reloads the timeline whenever it writes a new snapshot; until then the entries
        // carry the widget across midnight and end with "open Kenet".
        completion(Timeline(entries: entries(from: Date()), policy: .atEnd))
    }

    private func entries(from now: Date) -> [GoalChainEntry] {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup),
            let snapshot = WidgetSnapshotFile.read(from: WidgetSnapshotFile.url(in: container))
        else { return [GoalChainEntry(date: now, day: nil, vaultID: "")] }
        return snapshot.timeline(from: now, calendar: WidgetDay.deviceCalendar).map {
            GoalChainEntry(date: $0.date, day: $0.day, vaultID: snapshot.vaultID)
        }
    }
}

struct GoalChainEntryView: View {
    let entry: GoalChainEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GoalChainWidgetView(
            day: entry.day,
            link: family == .systemSmall ? nil : { WidgetSnapshot.link(for: $0, vaultID: entry.vaultID).url },
            layout: layout
        )
        .privacySensitive()
        .containerBackground(for: .widget) { WidgetTheme.paper }
        .widgetURL(WidgetLink.today.url)
    }

    private var layout: GoalChainLayout { family == .systemSmall ? .small : .medium }
}
