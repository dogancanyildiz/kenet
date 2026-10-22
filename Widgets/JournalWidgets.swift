import AppIntents
import SwiftUI
import WidgetKit

@main
struct JournalWidgets: WidgetBundle {
    var body: some Widget {
        GoalChainWidget()
    }
}

/// Home-screen chain widget (small, medium). It draws only the snapshot the app writes into the
/// App Group; it never opens the app's index. A tap on an open yes/no goal of an iCloud vault
/// marks it here (``MarkGoalInWidgetIntent``); every other tap opens the app with a
/// ``WidgetLink`` and the app marks the goal through its App Intent path.
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
    /// The snapshot the day came from: its vault and where the vault lives decide each tap.
    let snapshot: WidgetSnapshot?
}

struct GoalChainProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoalChainEntry {
        GoalChainEntry(date: Date(), day: nil, snapshot: nil)
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
        else { return [GoalChainEntry(date: now, day: nil, snapshot: nil)] }
        return snapshot.timeline(from: now, calendar: WidgetDay.deviceCalendar).map {
            GoalChainEntry(date: $0.date, day: $0.day, snapshot: snapshot)
        }
    }
}

struct GoalChainEntryView: View {
    let entry: GoalChainEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GoalChainWidgetView(
            day: entry.day,
            link: family == .systemSmall ? nil : { link(for: $0) },
            layout: layout,
            intent: family == .systemSmall ? nil : { intent(for: $0) }
        )
        .privacySensitive()
        .containerBackground(for: .widget) { WidgetTheme.paper }
        .widgetURL(WidgetLink.today.url)
    }

    private var layout: GoalChainLayout { family == .systemSmall ? .small : .medium }

    /// The row's link; an intent (below) takes its place where the widget marks itself.
    private func link(for goal: WidgetSnapshot.Goal) -> URL {
        guard let snapshot = entry.snapshot else { return WidgetLink.today.url }
        return WidgetSnapshot.link(for: goal, vaultID: snapshot.vaultID).url
    }

    private func intent(for goal: WidgetSnapshot.Goal) -> (any AppIntent)? {
        guard case .markInWidget(let id) = entry.snapshot?.tap(for: goal) else { return nil }
        return MarkGoalInWidgetIntent(goalID: id)
    }
}
