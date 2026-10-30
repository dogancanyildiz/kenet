import SwiftUI
import WidgetKit

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.lockScreen, provider: LockScreenProvider()) { entry in
            LockScreenEntryView(entry: entry)
        }
        .configurationDisplayName("widget.lock.name")
        .description("widget.lock.description")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct LockScreenEntry: TimelineEntry {
    let date: Date
    let day: WidgetSnapshot.Day?
    let hideContent: Bool
}

struct LockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockScreenEntry {
        .init(date: Date(), day: nil, hideContent: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenEntry) -> Void) {
        completion(entries(from: Date())[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockScreenEntry>) -> Void) {
        completion(Timeline(entries: entries(from: Date()), policy: .atEnd))
    }

    private func entries(from now: Date) -> [LockScreenEntry] {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup),
            let snapshot = WidgetSnapshotFile.read(from: WidgetSnapshotFile.url(in: container))
        else { return [.init(date: now, day: nil, hideContent: true)] }
        return snapshot.lockScreenTimeline(from: now, calendar: WidgetDay.deviceCalendar).map {
            .init(date: $0.date, day: $0.day, hideContent: snapshot.hideContent ?? true)
        }
    }
}

struct LockScreenEntryView: View {
    let entry: LockScreenEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LockScreenWidgetView(day: entry.day, date: entry.date, hideContent: entry.hideContent, layout: layout)
            .containerBackground(for: .widget) { Color.clear }
    }

    private var layout: LockScreenLayout {
        switch family {
        case .accessoryCircular: .circular
        case .accessoryInline: .inline
        default: .rectangular
        }
    }
}
