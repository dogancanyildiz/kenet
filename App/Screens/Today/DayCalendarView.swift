import SwiftUI
import VaultFormat

struct DayCalendarView: View {
    let date: CalendarDate
    @Environment(CalendarService.self) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        if calendar.showsSection(on: date) {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: String(
                        localized: "Takvim",
                        bundle: PresentationLocalization.bundle(locale), locale: locale))
                if calendar.authorization.canRequest {
                    Button("Takvim etkinliklerini göstermek için izin ver") {
                        Task { await calendar.requestAccess() }
                    }
                    .buttonStyle(InkTextButtonStyle())
                    .disabled(calendar.isRequesting)
                }
                if let error = calendar.errorText {
                    InfoBand(
                        kind: .warning, verbatim: error,
                        actionTitle: calendar.authorization.canRead ? "Yeniden dene" : nil,
                        action: calendar.authorization.canRead
                            ? { Task { await calendar.load(date) } } : nil)
                }
                ForEach(calendar.events(on: date)) { event in
                    InkCalendarRow(
                        time: startLabel(for: event),
                        title: event.title.isEmpty
                            ? String(
                                localized: "Başlıksız etkinlik",
                                bundle: PresentationLocalization.bundle(locale), locale: locale)
                            : event.title,
                        endLabel: endLabel(for: event)
                    )
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        Button {
                            draft(event)
                        } label: {
                            Label("Olay taslağı", systemImage: "square.and.pencil")
                        }
                    }
                    .accessibilityAction(named: Text("Olay taslağı")) { draft(event) }
                }
            }
        }
    }

    /// Rows exist only with read access; the day's quick entry bar picks the event up.
    private func draft(_ event: CalendarEvent) {
        CalendarDraftInbox.shared.post(event, on: date)
    }

    private func startLabel(for event: CalendarEvent) -> String? {
        if event.isAllDay {
            return String(
                localized: "Tüm gün", bundle: PresentationLocalization.bundle(locale),
                locale: locale)
        }
        return event.start.formatted(.dateTime.hour().minute().locale(locale))
    }

    private func endLabel(for event: CalendarEvent) -> String? {
        if event.isAllDay { return nil }
        let end: String
        if LocalDay.today(at: event.start) != LocalDay.today(at: event.end) {
            end = event.end.formatted(
                .dateTime.day().month(.abbreviated).hour().minute().locale(locale))
        } else {
            end = event.end.formatted(.dateTime.hour().minute().locale(locale))
        }
        return String(
            localized: "Until \(end)", bundle: PresentationLocalization.bundle(locale),
            locale: locale)
    }
}
