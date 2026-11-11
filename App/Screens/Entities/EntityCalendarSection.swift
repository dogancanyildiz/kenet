import SwiftUI

/// The person's upcoming calendar events, matched by name or alias in the title or among the
/// attendees (decision 2026-11-11). The vault stays as it is: nothing here writes a file.
@MainActor @Observable
final class EntityCalendarModel {
    private(set) var result: CalendarPersonEvents?

    func load(calendar: CalendarService, names: [String], now: Date) async {
        // From the start of today: an event already under way today still counts.
        let answer = await calendar.personEvents(names: names, from: Calendar.current.startOfDay(for: now))
        guard !Task.isCancelled else { return }
        result = answer
    }
}

struct EntityCalendarLoadKey: Hashable {
    let names: [String]
    let changes: Int
    let canRead: Bool
}

/// List rows of the section; the model is loaded from the page (an empty row is never mounted).
struct EntityCalendarSection: View {
    let name: String
    let model: EntityCalendarModel
    @Environment(\.locale) private var locale
    @State private var route: CalendarSheetRoute?

    var body: some View {
        if let result = model.result {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionHeader("Yaklaşan etkinlikler")
                    if result.birthday == nil {
                        Button {
                            route = .birthday(name: name)
                        } label: {
                            Text("Doğum günü ekle").tapTarget()
                        }
                        .buttonStyle(InkTextButtonStyle())
                        .accessibilityIdentifier("button.entity.addBirthday")
                    }
                }
                // On the always-present header row: a sheet on a `Section` never presents.
                .sheet(item: $route) { CalendarSheet(route: $0) }
                .inkListRow()
                if !result.upcoming.isEmpty {
                    InkCard(padded: true) {
                        ForEach(Array(result.upcoming.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { InkCardDivider() }
                            row(event)
                        }
                    }
                    .inkListRow()
                }
            }
        }
    }

    private func row(_ event: CalendarEvent) -> some View {
        let text = CalendarEventText(locale: locale)
        return Button {
            route = .detail(event, day: nil)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // The date is on the second line: a short margin cannot hold "11 Kas".
                InkCalendarRow(
                    time: nil, title: text.title(event),
                    endLabel: ([text.when(event)] + [text.caption(event)].filter { !$0.isEmpty })
                        .joined(separator: " · "))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("row.entity.calendarEvent")
    }
}
