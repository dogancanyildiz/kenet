import SwiftUI
import VaultFormat

struct DayCalendarView: View {
    let date: CalendarDate
    @Environment(CalendarService.self) private var calendar
    @Environment(\.locale) private var locale
    @State private var route: CalendarSheetRoute?

    private var text: CalendarEventText { CalendarEventText(locale: locale) }

    var body: some View {
        if calendar.showsSection(on: date) {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                header
                InkCard(padded: true) {
                    if calendar.authorization.canRequest {
                        // A small row, not a call to action: the day's writing comes first.
                        Button {
                            Task { await calendar.requestAccess() }
                        } label: {
                            Label("Takvim etkinliklerini göstermek için izin ver", systemImage: "calendar")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.ink.accent)
                                .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(calendar.isRequesting)
                    }
                    if let error = calendar.errorText {
                        InfoBand(
                            kind: .warning, verbatim: error,
                            actionTitle: calendar.authorization.canRead ? "Yeniden dene" : nil,
                            action: calendar.authorization.canRead
                                ? { Task { await calendar.load(date) } } : nil)
                    }
                    let events = calendar.events(on: date)
                    if calendar.authorization.canRead, events.isEmpty, calendar.errorText == nil {
                        Button {
                            route = .create(date)
                        } label: {
                            Label("Takvime etkinlik ekle", systemImage: "plus")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.ink.accent)
                                .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("button.calendar.addEmpty")
                    }
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { InkCardDivider() }
                        eventRow(event)
                    }
                }
            }
            .sheet(item: $route) { CalendarSheet(route: $0) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionHeader(
                title: String(
                    localized: "Takvim",
                    bundle: PresentationLocalization.bundle(locale), locale: locale))
            // An empty day has the card's "Takvime etkinlik ekle" row: one way to add, not two.
            if calendar.authorization.canRead, !calendar.events(on: date).isEmpty || calendar.errorText != nil {
                Button {
                    route = .create(date)
                } label: {
                    Image(systemName: "plus")
                        .tapTarget()
                }
                .buttonStyle(InkTextButtonStyle())
                .accessibilityLabel(Text("Takvime etkinlik ekle"))
                .accessibilityIdentifier("button.calendar.add")
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        Button {
            route = .detail(event, day: date)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // "13:00–14:00 · İş · Her hafta": one secondary line under the title, the
                // calendar's color before it.
                InkCalendarRow(
                    time: text.start(event), title: text.title(event),
                    endLabel: ([text.range(event)] + [text.caption(event)])
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                    calendarColor: CalendarColorDot(color: event.color))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("row.calendarEvent")
        .contextMenu {
            Button {
                draft(event)
            } label: {
                Label("Olay taslağı", systemImage: "square.and.pencil")
            }
        }
        .accessibilityAction(named: Text("Olay taslağı")) { draft(event) }
    }

    /// Rows exist only with read access; the day's quick entry bar picks the event up.
    private func draft(_ event: CalendarEvent) {
        CalendarDraftInbox.shared.post(event, on: date)
    }
}
