import SwiftUI
import WidgetKit

struct QuickEntryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.quickEntry, provider: QuickEntryProvider()) { entry in
            QuickEntryEntryView(date: entry.date)
        }
        .configurationDisplayName("widget.write.title")
        .description("widget.write.description")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct QuickEntryEntry: TimelineEntry {
    let date: Date
}

struct QuickEntryProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntryEntry { QuickEntryEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntryEntry) -> Void) {
        completion(placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntryEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: midnight) ?? now.addingTimeInterval(86400)
        completion(Timeline(entries: [QuickEntryEntry(date: now)], policy: .after(next)))
    }
}

private struct QuickEntryEntryView: View {
    let date: Date
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: "square.and.pencil")
                    .accessibilityLabel("widget.write.open")
            case .accessoryInline:
                Label("widget.write.open", systemImage: "square.and.pencil")
            default:
                QuickEntryWidgetView(date: date)
            }
        }
        .containerBackground(for: .widget) { WidgetTheme.paper }
        .widgetURL(WidgetLink.write.url)
    }
}
