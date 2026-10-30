import SwiftUI

/// Accessory content uses the system's vibrant foreground, never the paper/ink palette.
enum LockScreenLayout: CaseIterable, Sendable {
    case rectangular, circular, inline
}

struct LockScreenWidgetView: View {
    let day: WidgetSnapshot.Day?
    let date: Date
    let hideContent: Bool
    let layout: LockScreenLayout

    var nextEvent: WidgetSnapshot.Event? {
        day?.events?.filter { $0.end > date }.min { $0.start < $1.start }
    }

    var taskText: String {
        String(format: String(localized: "widget.lock.tasks"), day?.openTaskCount ?? 0)
    }

    var eventText: String? {
        guard let event = nextEvent else { return nil }
        let time =
            event.isAllDay
            ? String(localized: "widget.lock.allDay")
            : event.start.formatted(date: .omitted, time: .shortened)
        return hideContent || event.title.isEmpty ? time : "\(time) · \(event.title)"
    }

    var emptyText: String? {
        guard let day else { return String(localized: "widget.lock.open") }
        // An older snapshot has neither field: ask the app for a fresh one.
        if day.events == nil && day.openTaskCount == nil { return String(localized: "widget.lock.open") }
        if nextEvent == nil && (day.openTaskCount ?? 0) == 0 { return String(localized: "widget.lock.empty") }
        return nil
    }

    var body: some View {
        Group {
            if let emptyText {
                Text(emptyText).font(WidgetTheme.meta).minimumScaleFactor(0.7)
            } else {
                switch layout {
                case .rectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        if let eventText { Text(eventText).font(WidgetTheme.section).lineLimit(1) }
                        Text(taskText).font(WidgetTheme.meta).lineLimit(1)
                    }
                case .circular:
                    VStack(spacing: 1) {
                        Text("\(day?.openTaskCount ?? 0)").font(.system(.title2, weight: .semibold)).monospacedDigit()
                        Image(systemName: "checklist").font(.caption2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(taskText)
                case .inline:
                    Text([eventText, taskText].compactMap { $0 }.joined(separator: " · "))
                        .font(WidgetTheme.meta).lineLimit(1)
                }
            }
        }
        .privacySensitive()
        .widgetURL(WidgetLink.today.url)
    }
}
